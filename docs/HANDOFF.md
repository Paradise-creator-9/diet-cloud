# HANDOFF — 膳食志 / Diet Cloud 项目交接

> 本文档基于对仓库源码、`supabase/*.sql`、Vercel `api/*.js`、以及通过 Supabase MCP 只读查询到的**生产库实际状态**整理，而非仅凭 README。所有"待确认"项已明确标注原因。首次生成时 HEAD 为 `a1038b9`；已于同步 `origin/main`（fast-forward 13 个提交）后基于 HEAD `ec396b9` 重新核实，结论按最新代码更新（见下方"当前状态"）。

## 1. 项目概览

### 用途
面向单一用户（本人）的私人减脂/健康复盘面板，非通用多租户产品。核心诉求：手机拍餐食照片 → AI 辅助估算营养 → 结合体重体脂、Apple 健康运动数据做趋势复盘。参见 [PROJECT_CONTEXT.md](../PROJECT_CONTEXT.md)。

### 已实现功能
- 饮食记录：手动录入 + Gemini 照片识别，四餐分类，卡路里/蛋白/碳水/脂肪/纤维。
- 身体数据：手动录入 + 体脂秤截图 Gemini 识别，含分段身体数据（左右臂/腿、躯干）。
- 运动数据：Apple 健康导出 zip 前端解析导入、iPhone 快捷指令服务端同步接口。
- 趋势分析、照片库、常吃食物快捷添加、目标环（仅本地存储，见下文"待确认/已知缺口"）。
- Liquid Glass 视觉系统正在迁移中：`src/design-system/`（`GlassCard`/`GlassButton`/`GlassModal`/`AuroraBackground` 等）已被 `src/main.tsx:49` 引入并用于登录页、总览卡片等（见 commit `f0a2d58`→`a1038b9`）；`design-system.html` + `src/design-system/demo.tsx` 是独立的组件预览页，不属于主应用运行路径。`demo.html` + `src/demo.tsx` 是一个无关的 GSAP+Three.js 技术验证页，与业务无关。

### 技术栈
| 层 | 技术 |
| --- | --- |
| 前端 | React 19 + TypeScript 5 + Vite 6，单页应用，无路由库（视图切换靠 state） |
| 状态/动效 | zustand（design-system 内使用）、framer-motion、gsap、three/@react-three/fiber（用于 demo.tsx 技术预览，**非主业务视图**——待确认：是否计划正式引入 3D 效果到主 App） |
| 后端数据 | Supabase：Auth（Email OTP）、Postgres（RLS 逐表隔离）、Storage（`meal-photos` bucket，私有+签名 URL） |
| 服务端函数 | Vercel Functions（Node，`api/*.js`，非 Edge Runtime） |
| AI | Gemini `generateContent`，多模型 fallback（`api/gemini.js`） |
| 部署 | Vercel，`vercel.json` 指定 `framework: vite` |

### 前端/后端/数据库/Storage/Auth/AI 关系
```
Browser (React SPA)
  ├─ VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY → Supabase Auth/Postgres/Storage（受 RLS 约束）
  └─ fetch → Vercel Functions (api/*.js)
              ├─ analyze-meal.js / analyze-body.js → Gemini API（GEMINI_API_KEY，服务端专用；端点已要求 Supabase 用户 session 鉴权 + 按用户内存限流，见 AUDIT.md #4）
              ├─ ingest.js / activity-ingest.js → Supabase service-role client（绕过 RLS，靠 DIARY_INGEST_TOKEN 静态 Bearer Token 鉴权）
              └─ gemini.js → 模型 fallback 与重试封装，被 analyze-*.js 复用
```
详见 [ARCHITECTURE.md](../ARCHITECTURE.md)（内容与当前代码一致，未发现过期描述）。

### 本地运行 / 部署
```bash
npm install
npm run dev      # vite --host 127.0.0.1
npm run build    # tsc && vite build → dist/
npm run preview
```
Vercel：`vercel.json` 设 `buildCommand: npm run build`、`outputDirectory: dist`、`framework: vite`；环境变量需在 Vercel Project Settings 单独配置（`.env.local` 不会被部署使用）。

## 2. 核心目录

| 路径 | 作用 |
| --- | --- |
| `src/main.tsx`（3907 行） | 应用主体：状态管理、全部页面/弹窗、本地计算逻辑。**单文件过大，是后续重构首要对象**（README/TODO.md 已自述）。 |
| `src/supabase.ts`（875 行） | 数据访问层：Auth、四张表 CRUD、Storage 上传/签名 URL、Apple 健康批量写入。 |
| `src/appleHealth.ts` + `appleHealthWorker.ts` | Apple 健康导出 zip 的流式正则解析（非标准 XML parser），跑在 Web Worker。 |
| `src/data.ts` | 未配置 Supabase 时的本地演示种子数据（`isCloudConfigured=false` 时启用）。 |
| `src/utils.ts` | 日期格式化、汇总计算、图片压缩等纯函数。 |
| `src/design-system/` | Liquid Glass 组件库（部分已被 main.tsx 引用，部分仅用于独立 demo）。 |
| `api/analyze-meal.js` / `api/analyze-body.js` | Gemini 图片/文字识别端点，要求 `Authorization: Bearer <Supabase access token>`（`api/_lib/sessionAuth.js`），并按已验证用户 id 做进程内内存限流（10 分钟窗口、12 次/用户，见 AUDIT.md #4 的局限说明）。 |
| `api/ingest.js` / `api/activity-ingest.js` | service-role 直写端点，Bearer Token 鉴权，供脚本/快捷指令使用。 |
| `api/gemini.js` | Gemini 请求封装：模型 fallback、重试、错误分类。 |
| `supabase/schema.sql` | 主 schema：四张表 + RLS + `meal-photos` bucket 声明。**与生产库当前状态存在差异，见下方"数据库"章节的重要提示。** |
| `supabase/*.sql`（其余 8 个文件） | 历史补丁/修复脚本，非 CLI migration，需手动在 SQL Editor 执行。 |
| `scripts/*.mjs` | 一次性导入/发送脚本，用 service-role key 本地运行。 |

## 3. 数据库

> 通过 Supabase MCP 只读连接到生产项目核实：4 张表均 `rls_enabled=true`，行数分别为 `food_items=148`、`body_metrics=11`、`daily_activities=190`、`exercise_activities=23`，`public` schema 下**没有任何自定义 function/trigger/RPC**。同步 `origin/main` 到 `ec396b9` 后已重新查询一次，行数与策略文本均与首次检查完全一致（预期之内——本次同步的 13 个提交不含任何数据库/Storage 相关改动）。（生产项目的具体 ID/URL 不记录在本文档中。）

### 表结构（字段/约束见 `supabase/schema.sql`，已核对与生产一致）

| 表 | 主键 | 唯一约束 | 索引 | 说明 |
| --- | --- | --- | --- | --- |
| `food_items` | `id uuid` | `(user_id, source_id) where source_id is not null` | `(user_id, eaten_on desc, created_at)`、`(user_id, meal)` | `meal` 为枚举 `breakfast/lunch/dinner/snack`；`photo_urls text[]` 存的是 **Storage 路径**，不是真实 URL（字段名有误导性）；所有数值列 `check(>=0)`。 |
| `body_metrics` | `id uuid` | `(user_id, measured_on)` — 每人每天一条 | `(user_id, measured_on desc)` | 含躯干/四肢分段体脂肌肉字段（体脂秤截图识别专用）。 |
| `daily_activities` | `id uuid` | `(user_id, activity_on, source)` | `(user_id, activity_on desc)` | `raw_metrics jsonb` 保留原始 Apple 健康分类明细；`source` 区分 `apple_health` / `apple_shortcut` / `manual` 等。 |
| `exercise_activities` | `id uuid` | `(user_id, source, external_id)` | `(user_id, activity_on desc, started_at desc)` | `external_id` 对 Apple 健康导入是确定性 hash（`appleHealth.ts` 内 `stableExternalId`），保证重复导入幂等。 |

全部四张表外键 `user_id → auth.users(id) on delete cascade`，RLS 策略均为 `using/with check (auth.uid() = user_id)`，逐表 select/insert/update/delete 各一条策略，**无跨用户读写口子**（生产库已核实策略文本与 `schema.sql` 一致）。

### RPC / Trigger / Function
**无**。所有写入都是前端直接 `insert/update/upsert/delete`，或服务端用 service-role client 直接操作表；没有数据库函数或触发器承担业务逻辑（例如没有自动重算每日汇总的 trigger——汇总是纯前端 `utils.ts: totalsFor()` 内存计算）。

### Storage SQL 与生产库状态（已在 `fix/pre-public-security` 分支修复，见 AUDIT.md #1）
`supabase/schema.sql` 与 `supabase/fix-meal-photos-storage-permissions.sql` 曾把 `meal-photos` bucket 声明为 `public: true`，并附一条无用户范围限制的 `meal_photos_public_read` 读策略，而**生产库实际状态**（MCP 只读核实）一直是 `public: false` + 按 `(storage.foldername(name))[1] = auth.uid()` 隔离的 `meal_photos_read_own` 读策略——生产项目 migration 历史里有一条对应记录（`20260708041749_restrict_meal_photos_read_to_owner`），但仓库当时没有 `supabase/migrations/` 目录，这条记录只存在于生产项目，没有同步回仓库。

**现状**：两份 SQL 文件已改为与生产库一致的私有 bucket + `meal_photos_read_own` 策略；新增 `supabase/migrations/` 目录，`20260708041749_restrict_meal_photos_read_to_owner.sql` 是从生产项目 `schema_migrations` 表只读查询出的逐字原文，`20260712000000_set_meal_photos_bucket_private.sql` 是补上"bucket `public=false` 从未被任何 migration 记录"这个缺口的新后续 migration。insert/update/delete 三条策略在仓库里本来就是对的，这次只改了 bucket 标志和 SELECT 策略。**本轮只改了仓库文件，没有对生产环境执行任何写操作或应用任何 migration**（只读核实过生产状态未变）。SQL 的语法/执行层面正确性已在本地 Docker + Supabase CLI 搭建的一次性非生产实例上完成真实验证（验证后已完全销毁，容器、卷、临时目录均已清理）：全新环境执行 `schema.sql` 零错误、结果与预期一致；模拟旧公开状态后按顺序执行两个 migration 成功升级为私有状态且不删除已有对象；用两个真实测试账号对 Storage REST API 做了跨用户权限行为测试，14 项检查全部通过（详见 AUDIT.md #1）。仍然只做了文本层面的静态回归测试（`supabase/storage-policy.test.mjs`）作为持续回归防线，不依赖每次都要跑真实数据库。

### 数据创建/修改/删除流程
- **创建**：前端 `insert`（`food_items`/`exercise_activities` 手动新增）或 `upsert`（`body_metrics` 按 `user_id+measured_on`、`daily_activities` 按 `user_id+activity_on+source`）。
- **修改**：`update`，逐字段覆盖；`food_items` 编辑时会 diff 新旧 `photo_urls` 清理孤儿照片（非原子操作，见 AUDIT.md）。
- **删除**：`delete`，`food_items` 删除同时尝试清理 Storage 中不再被引用的照片路径。
- **Apple 健康导入**：`daily_activities` 对 `source='apple_health'` 采用"先删范围内旧数据再整批 upsert"（非增量合并）；`exercise_activities` 靠确定性 `external_id` upsert 去重。

## 4. Authentication

- **注册/登录**：仅 Email Magic Link（OTP），`supabase.auth.signInWithOtp({ email, options: { emailRedirectTo: window.location.origin } })`（`src/supabase.ts:341`）。无密码登录。
- **Session 恢复**：交给 Supabase JS SDK 持久化（`persistSession: true`、`autoRefreshToken: true`、`detectSessionInUrl: true`，`src/supabase.ts:14-18`）。同步后代码显示登录态判定逻辑已重构（commit `c36eacf`）：`App()` 现在直接消费 `onAuthChange` 的首次回调（`src/main.tsx` 内 `useEffect`）而不是额外调用一次 `getUser()`，并加了 6 秒兜底超时防止登录页卡死；`onAuthChange` 的回调签名也改为直接传出 `session.user`（`src/supabase.ts:335`）。这是一处 bug 修复，不改变鉴权方式本身（仍是纯 Email OTP + SDK 会话）。
- **退出**：`supabase.auth.signOut()`。
- **用户资料创建**：**没有 `profiles` 表，没有注册后建档步骤**。所有业务表靠 `user_id uuid ... default auth.uid()` 隐式关联到 `auth.users`，用户"存在"即等价于 `auth.users` 里有一条记录。
- **客户端 vs 服务端职责**：客户端用 anon key，所有读写受 RLS 约束；服务端两个 ingest 端点（`api/ingest.js`、`api/activity-ingest.js`）用 service-role key **完全绕过 RLS**，靠静态 Bearer Token 校验（`DIARY_INGEST_TOKEN`）。

**为什么 ingest 端点仍用 service-role（`fix/pre-public-security` 分支核实）**：这两个端点没有浏览器会话背后支撑——全仓库搜索确认 `src/` 里没有任何前端 `fetch()` 调用它们，唯一的调用方是 iPhone 快捷指令自动化任务和本地脚本 `scripts/send-ingest.mjs`，两者都不具备维护一个会过期刷新的 Supabase 用户 session 的能力。因此改造成"验证 Supabase 用户 JWT"并不适用——没有 JWT 可验证。已修复的是另一半问题：**身份来源**。`api/_lib/ingestAuth.js` 里的 `resolveTrustedUserId()` 现在只信任服务端环境变量 `DIARY_USER_ID`/`DIARY_USER_EMAIL` 来决定写入目标账号，完全不再信任请求体里的 `userId`/`userEmail` 字段（旧代码曾优先采用请求体字段，构成 IDOR，见 [AUDIT.md](AUDIT.md) #2，现已修复）；若请求体仍附带这两个字段且与服务端配置的账号不一致，会被直接拒绝（403）并记录一条不含敏感信息的日志。`DIARY_INGEST_TOKEN` 本身依然是这两个端点唯一的认证因子，这是与其"无浏览器会话的单用户自动化通道"定位相匹配的设计，不是遗留问题。**同一分支的后续 commit** 进一步收紧了这个认证因子的传递方式：`requireIngestToken()` 现在只接受标准 `Authorization: Bearer <token>` header，已移除 URL query 参数（`token`/`diaryToken`/`apiKey`/`key`）和自定义 `x-diary-token` header 两条兼容路径——单纯携带 query token 的请求会被直接拒绝（`400 query_token_not_supported`），即使同时带了正确的 Authorization header 也一样，强制调用方彻底清理 URL。token 比较也从字符串 `!==` 改为 `node:crypto` 的 `timingSafeEqual` 恒定时间比较。**副作用**：任何仍在用旧版"URL 参数法"配置的 iPhone 快捷指令，部署新版本后会立即失效，需要用户手动把 Token 从 URL 移到 Header（见 [docs/apple-health-shortcut.md](apple-health-shortcut.md) 和应用内"iPhone 快捷指令同步"说明的更新版文字）。

## 5. Storage

- **Bucket**：`meal-photos`（名称来自 `VITE_SUPABASE_STORAGE_BUCKET` / `SUPABASE_STORAGE_BUCKET`，默认硬编码回退到 `"meal-photos"`）。生产库当前为**私有 bucket**（见上文数据库章节的核实结果）。
- **路径格式**：`${userId}/${date}/${timestamp}-${安全文件名}`（前端上传，`src/supabase.ts:415`）；服务端 ingest 路径为 `${userId}/${date}/${安全文件名}`（`api/ingest.js:96`，**`date` 字段未做路径穿越字符过滤**，见 AUDIT.md）。
- **用户隔离**：靠路径首段 = `auth.uid()` 的 Storage RLS 策略（insert/update/delete/select 四条策略镜像一致）。
- **上传**：前端先用 `utils.ts` 里的压缩函数把照片压到 ~300KB 再传；`upsert:false`（正常上传）/`upsert:true`（导入历史数据场景）。
- **读取**：不用 `getPublicUrl`，改用批量 `createSignedUrls`（24 小时 TTL，`PHOTO_SIGNED_URL_TTL_SECONDS`，`src/supabase.ts:317`），已废弃的旧数据里可能仍有 `http`/`/` 开头的绝对路径会原样透传。
- **删除**：`removeUnreferencedPhotoPaths` 先查询是否还有 `food_items` 行引用该路径，再决定是否物理删除——**非事务操作，存在竞态**（并发编辑可能导致误删或漏删，见 AUDIT.md）。

## 6. 核心业务规则

| 主题 | 说明 |
| --- | --- |
| 饮食记录结构 | `food_items` 一行 = 一个食物条目，非"一餐一行"；同一餐可有多条。四餐枚举固定，无自定义餐次。 |
| 份量与单位 | `grams` 为唯一份量字段（数值，无单位枚举），前端展示层自行拼接"g"。 |
| 卡路里/三大营养素 | **纯前端计算**：`utils.ts: totalsFor()` 对当日 `food_items` 数组求和，无服务端/数据库层聚合或校验；写入时数值来自 AI 识别或手动输入，只有 DB `check(>=0)` 兜底，无上限校验。 |
| 图片与记录关联 | `food_items.photo_urls text[]` 存多个 Storage 路径；一条记录可关联 0~N 张图。 |
| AI 识别流程 | 前端先取当前 Supabase session 的 access token（`getAccessToken()`，无 token 则直接报错、不发请求）→压缩→base64 dataURL→POST `/api/analyze-meal`（或 `/api/analyze-body`），带 `Authorization: Bearer <token>`→服务端验证 session + 限流通过后调用 Gemini→服务端 `normalizeAnalysis()` 做数值兜底（非法值→0）→前端二次校验并允许用户逐项编辑→用户确认后才写库。**AI 输出全程不直接落库**，必须过一次可编辑表单。`/api/analyze-meal.js`（commit `385dde8`/`e44202c`）支持**纯文字分析**——只要 `hint` 非空即可在不上传照片的情况下调用，服务端会切换成"完全依据文字描述估算"的 prompt 分支，并把 `confidence` 明显调低、在 `notes` 里提示用户核对份量；文字模式与图片模式共用同一鉴权/限流网关。 |
| 编辑/删除 | 编辑走 `update`，删除走 `delete`+孤儿照片清理；均无软删除/回收站。 |
| 每日统计/历史 | 全部由前端 `useMemo` 基于已拉取的全量数据在内存里按 `selectedDate` 切片计算，没有分页/按需拉取（当前数据量小，未来数据量增大需关注全量拉取的可扩展性）。 |
| 日期/时区 | **前端**：一律用浏览器本地 `Date`（`main.tsx: dateKey()`），无 UTC 转换、无时区库。**服务端**：`api/activity-ingest.js` 的 `todayKey()` 硬编码 `Intl.DateTimeFormat(..., { timeZone: "Asia/Tokyo" })` 作为"今天"兜底（当请求未显式传 `date` 时）。两者理论上可能在日期边界附近不一致（例如用户设备不在东京时区时）。**待确认**：用户本人实际使用时区是否始终为 Asia/Tokyo——如果是，这个硬编码是有意为之而非 bug。 |
| 用户目标/个人设置 | `UserGoals`（每日热量/蛋白/纤维/目标体重体重等）**只存在浏览器 `localStorage`**（key 形如 `diet-cloud-goals-v1`），**没有对应的 Supabase 表**，不跨设备同步，也不支持训练日/休息日差异化目标（TODO.md 中列为待办功能，代码里确认尚未实现）。 |

## 7. 外部服务与环境变量

| 变量 | 用途 | 使用方 | 敏感 |
| --- | --- | --- | --- |
| `VITE_SUPABASE_URL` | Supabase 项目 URL | 浏览器 | 否 |
| `VITE_SUPABASE_ANON_KEY` | Supabase 匿名公钥 | 浏览器 | 否（受 RLS 保护，可公开） |
| `VITE_SUPABASE_STORAGE_BUCKET` | 照片 bucket 名 | 浏览器 | 否 |
| `SUPABASE_URL` | 服务端 Supabase URL | Vercel Functions / 本地脚本 | 否 |
| `SUPABASE_SERVICE_ROLE_KEY` | 绕过 RLS 的服务端写入 | Vercel Functions / 本地脚本 | **是，禁止提交/暴露** |
| `SUPABASE_STORAGE_BUCKET` | 服务端照片 bucket 名 | Vercel Functions / 本地脚本 | 否 |
| `DIARY_INGEST_TOKEN` | `/api/ingest`、`/api/activity-ingest` 的静态 Bearer 鉴权 | 服务端 + 快捷指令/脚本调用方 | **是** |
| `DIARY_USER_EMAIL` | 服务端按邮箱定位目标用户 | 服务端 | 是（个人信息） |
| `DIARY_USER_ID` | 本地脚本/服务端直接指定目标用户 UUID | 服务端/本地脚本 | 是（个人标识符） |
| `GEMINI_API_KEY` | Gemini 图片分析 | 服务端 | **是** |
| `GEMINI_MODEL` / `GEMINI_MODELS` | 指定/覆盖模型 fallback 列表 | 服务端 | 否 |
| `LOCAL_DIARY_DATA` / `DIARY_PHOTO_PATH` | 本地一次性导入脚本路径覆盖 | 本地脚本 | 否 |

## 8. 当前状态（检查时点）

- 分支：`main`；本地 HEAD `ec396b9`，**已通过 `git pull --ff-only` 与 `origin/main` 同步一致**（首次检查时 HEAD 为 `a1038b9`，落后 13 个提交；已 fast-forward，无 merge commit，无冲突）。
- 这 13 个提交只涉及：UI/交互（`src/main.tsx`、`src/styles.css` 的 Liquid Glass 视觉扩展、移动端修复、性能修复）、`api/analyze-meal.js`（新增纯文字 AI 分析）、`src/supabase.ts`（登录状态回调修复）、`.gitignore`（新增 `.vercel`、`.env*` 两条规则，与已有的 `.vercel/`、`.env`/`.env.*` 规则效果重叠，非实质变化）。**`supabase/`、`api/ingest.js`、`api/activity-ingest.js`、`api/analyze-body.js`、`api/gemini.js`、`README.md`、`package.json`、`docs/` 均未变化**（已用 `git diff --stat` 逐一确认为空）。
- 工作区：无已跟踪文件的改动；存在未跟踪文件/目录：`.claude/`、`demo.html`、`design-system.html`、`src/demo.tsx`（均为分析范围外的辅助/预览资产，同步前后均未做任何改动）。
- 构建：`npm run build`（`tsc && vite build`）在同步后的 `ec396b9` **再次执行通过**，`tsc` 无报错，`vite build` 产出 `dist/`（仅有 framer-motion "use client" 指令的无害警告 + 主 bundle ~793KB 的体积提示，无编译错误）。
- Lint/Test/Typecheck/CI：同步后重新检查，**仍均无独立命令/配置**。`package.json` 脚本不变（`dev/build/preview/import:local`）；无 ESLint/Prettier/Vitest/Playwright 配置文件，无 `.github/` 目录——与 `TODO.md`"工程质量"章节的自述一致，非新发现。
