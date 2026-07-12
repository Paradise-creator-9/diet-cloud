# IOS_GUIDE — 原生 iOS App 开发指引

> 面向即将规划原生 iOS App 的开发助手。前提结论：后端（Supabase + Vercel Functions）现已可直接复用。细节证据见 [HANDOFF.md](HANDOFF.md) 和 [AUDIT.md](AUDIT.md)。本文档已在同步 `origin/main`（HEAD `ec396b9`）后重新核实；随后在 `fix/pre-public-security` 分支依次修复了 `ingest.js`/`activity-ingest.js` 的越权写入问题、`analyze-meal.js`/`analyze-body.js` 的无鉴权问题、ingest token 可经 URL query string 传递的问题，以及 Storage SQL 与生产库状态不一致的问题（均尚未合并入 main，见"已解决"小节）。目前 AUDIT.md 中已无标记"是否阻塞 iOS：是"的未处理项。

## 1. 可复用能力

| 能力 | 复用方式 | 备注 |
| --- | --- | --- |
| 数据库表 | `food_items`、`body_metrics`、`daily_activities`、`exercise_activities` 原样复用 | 结构见 HANDOFF.md 数据库章节；RLS 已按 `auth.uid()` 逐用户隔离，iOS 端只要用登录用户的 session 即可安全直连。 |
| Auth | Supabase Auth（Email OTP）可直接用 Supabase Swift SDK 调用 | 无密码体系，iOS 需实现"输入邮箱→收验证码/魔法链接→深链接回 App 完成登录"的原生流程（Web 版靠 `emailRedirectTo: window.location.origin` 跳回网页，iOS 需要改成 Universal Link 或自定义 URL Scheme）。 |
| Storage | `meal-photos` bucket，路径 `${userId}/${date}/${文件名}` | 生产库已是私有 bucket + 按用户目录隔离的 RLS（见 HANDOFF.md），iOS 直接用 Supabase Storage Swift SDK 上传/签名读取即可，**但要先把仓库 `supabase/schema.sql` 等文件同步成生产库的真实状态**（AUDIT.md #1），避免以后任何人依据仓库文件重建环境时又变回公开桶。 |
| Edge Functions / API | `api/analyze-meal.js`、`api/analyze-body.js`（Gemini 识别）、`api/ingest.js`、`api/activity-ingest.js`（service-role 写入） | 识别类端点可直接被 iOS 调用，但**当前完全没有身份校验**，必须先加认证（见"安全要求"）。ingest 类端点是为脚本/快捷指令设计的单用户直写通道，**不建议 iOS App 直接使用**——iOS 应该走 Supabase 客户端 SDK + RLS，而不是共享的 service-role 通道。 |
| AI 分析能力 | Gemini 多模型 fallback 封装（`api/gemini.js`） | 逻辑与 Provider 无关，可原样复用为 iOS 背后的识别服务，无需改写。 |
| 现有业务规则 | 四餐枚举、每日汇总纯前端计算、AI 结果需用户确认才落库、Apple 健康导入的去重策略（幂等 external_id） | 这些规则都不在数据库层强制，iOS 端需要在 Swift 侧重新实现同样的规则（不能假设后端会校验）。 |

## 2. Web → iOS 功能映射

| 功能 | 数据来源 | 使用的表/API | 关键业务规则 | 主要风险 |
| --- | --- | --- | --- | --- |
| 启动与 Session 恢复 | Supabase Auth SDK 本地持久化 session | `auth.getSession()` | 无自定义 token 存取逻辑，纯 SDK 行为 | iOS 需确认 Supabase Swift SDK 的 session 持久化机制（Keychain）与 Web 的 localStorage 行为不同，不能假设"已登录"状态可跨端共享 cookie/token。 |
| 注册与登录 | Email OTP | `auth.signInWithOtp` | 无密码、无用户资料表 | 深链接回跳需要 Universal Link 配置；**待确认**：Supabase 项目 Auth 设置里 Magic Link 的跳转白名单是否已包含 iOS 侧的回调地址。 |
| 今日饮食 | `food_items` 按 `eaten_on` 过滤 | `select` + RLS | 四餐分组、纯前端求和 | 全量拉取模式在 Web 端可行是因为数据量小（148 行），iOS 若做同样的"全量拉取再内存过滤"需评估长期数据量增长后的性能。 |
| 添加餐次和食物 | 手动表单 | `insert` | 数值只有 `>=0` 校验，无上限 | 需要在 iOS 客户端自行加合理性校验（Web 端也没有，属已知缺口，见 AUDIT.md）。 |
| 图片拍摄或选择 | `PHPickerViewController` / `UIImagePickerController` | Storage 上传 | Web 端有"每人每天 5 张"配额，**仅前端强制** | 服务端未强制配额，iOS 若也只在客户端限制，配额可被绕过（现状本就如此，非 iOS 引入的新风险，但要意识到）。 |
| AI 食物识别 | 照片和/或文字描述 → `/api/analyze-meal` | Vercel Function → Gemini | AI 结果必须先给用户编辑确认，不能直接落库；同步后确认该端点已支持**纯文字（无照片）分析**（服务端按 `hint` 是否有值切换 prompt 分支，`confidence` 会相应调低） | 端点当前无鉴权，任何人都能消耗 Gemini 额度；纯文字模式调用成本更低、更易被脚本化滥用，iOS 上线前必须先补上认证（见下）。 |
| 编辑和删除记录 | `update` / `delete` | 同上 | 删除食物记录时需联动清理孤儿照片 | Web 端的孤儿照片清理逻辑非原子操作（TOCTOU），iOS 若照搬同样逻辑会有相同竞态，建议后端化或接受当前风险等级。 |
| 每日营养统计 | 内存聚合 | 无独立 API，直接对 `food_items` 求和 | 无数据库层聚合函数 | 若 iOS 想要更高效的统计，可以考虑新增一个只读 view 或 RPC，但这是"可以后续解决"的优化项，非阻塞项。 |
| 历史记录和日历 | 按日期分组 | `food_items`/`body_metrics`/`daily_activities` 各自查询 | 无跨表联合查询/视图 | 三张表要分别拉取再在客户端按日期对齐，iOS 数据层要重建这套拼装逻辑。 |
| 用户目标 | **仅 `localStorage`，无后端** | 无 | 无训练日/休息日区分 | **这是唯一一个"数据层完全不存在"的功能**——iOS 要么继续做纯本地存储（不跨设备同步，与 Web 数据也不互通），要么新增一张 `user_goals` 表（推荐，见路线图）。 |
| 个人资料和设置 | 无独立表 | `auth.users` 元数据（未使用） | 无 profile 表 | 若 iOS 需要头像/昵称等资料，需要新建表；当前 Web 端完全没有这类功能可参考。 |

## 3. iOS 架构建议

简洁方案，不追求过度设计：

- **UI**：SwiftUI。
- **并发**：Swift Concurrency（`async/await`），避免引入 Combine 造成双范式混用。
- **后端 SDK**：`supabase-swift`（官方），封装 Auth / Postgrest / Storage 三个子模块。
- **分层**：Feature 模块 + Repository 层——每个业务域（饮食、身体、运动、趋势）一个 Feature 文件夹，内部再拆 View / ViewModel（或 `@Observable` State）/ Repository。Repository 是唯一直接调用 Supabase SDK 的地方，Feature 层不直接持有 Supabase client。
- **依赖注入**：轻量协议注入（不需要引入第三方 DI 容器），Repository 以协议暴露，方便单元测试用 mock 替换。
- **密钥存储**：`SUPABASE_URL` + anon key 可作为编译期常量（本身设计为可公开），**不需要 Keychain**；Keychain 仅用于存 Supabase session 的 refresh token（若 SDK 未自动处理，需手动接入）。
- **测试**：`XCTest`，重点覆盖 Repository 层的数据映射（Postgres row ↔ Swift struct）和日期/时区边界逻辑（当前 Web 端这块最薄弱，iOS 不应该重蹈覆辙）。

### 建议目录结构（仅目录职责，不生成 Swift 代码）
```
DietCloudiOS/
├── App/                      # App 入口、启动流程、深链接处理
├── Core/
│   ├── Networking/           # Supabase client 初始化、环境变量管理
│   ├── DateHandling/         # 统一的"今天"/时区计算，避免重蹈 Web 端本地时区问题
│   └── Keychain/             # session token 存取封装（如需手动介入 SDK 行为）
├── Features/
│   ├── Auth/                 # 登录、OTP 校验、深链接回跳
│   ├── TodayDiary/           # 今日饮食：列表、添加、编辑
│   ├── MealCapture/          # 拍照/选图或纯文字描述 → AI 识别 → 编辑确认 → 保存
│   ├── BodyMetrics/          # 身体数据 + 截图识别
│   ├── Exercise/             # 运动数据、Apple 健康导入（HealthKit 替代 zip 导出）
│   ├── Trends/                # 趋势图表、复盘
│   ├── PhotoLibrary/          # 照片库
│   └── Goals/                 # 目标设置（需先决定本地存储 vs 新表）
├── Repositories/              # 每个 Feature 对应一个 Repository，封装 Supabase 调用
└── Tests/
```

**HealthKit 替代方案提示**：iOS 原生可直接用 `HealthKit` API 读取运动/身体数据，**不需要**照搬 Web 端"解析 Apple 健康导出 zip"的笨重路径（那是 Web 端因为拿不到 HealthKit 权限才做的折中方案）。这是 iOS 相对 Web 的明显优势，建议路线图里单列。

## 4. 安全要求

| 项目 | 结论 |
| --- | --- |
| App 内允许使用的 Supabase 配置 | `SUPABASE_URL` + `anon key` —— 设计上可公开，可编译进 App。 |
| 绝不能放入 App 的密钥 | `SUPABASE_SERVICE_ROLE_KEY`、`GEMINI_API_KEY`、`DIARY_INGEST_TOKEN`。这几个key一旦进入 iOS 包体即可被逆向提取，等同于完全绕过 RLS/花费无限 Gemini 额度。 |
| 必须留在服务端的逻辑 | Gemini 调用（`api/analyze-meal.js`/`api/analyze-body.js`）——iOS 应该继续通过 Vercel Functions 中转，**不要**让 iOS 直接拿 `GEMINI_API_KEY` 调 Google API。 |
| RLS 是否足以保护用户数据 | **四张业务表足够**（`auth.uid()=user_id` 精确隔离，已用 MCP 核实生产库策略文本）。 |
| Storage 是否实现用户隔离 | **生产库已隔离**（私有 bucket + 按 `auth.uid()` 目录限定的读策略）；**仓库 SQL 文件已在 `fix/pre-public-security` 分支修复**，与生产库策略一致（AUDIT.md #1）。iOS 团队现在照抄 `supabase/schema.sql` 或 `supabase/migrations/` 初始化新环境会直接得到正确的私有+隔离状态。SQL 的语法/执行层面正确性和跨用户权限行为已在本地 Docker + Supabase CLI 的一次性非生产实例上做过真实验证（全新环境 bootstrap、旧状态升级 migration、两个真实测试账号的跨用户 Storage API 权限测试均通过，验证后环境已销毁，见 AUDIT.md #1）；iOS 团队仍建议在自己的项目上按同样方式跑一次，不必只依赖这份记录。 |
| Edge Function 是否验证用户身份 | `analyze-meal.js`/`analyze-body.js` **已在 `fix/pre-public-security` 分支修复**：确认这两个端点只被网页登录后渲染的 UI 调用（应用顶层未登录时直接返回登录页，见 HANDOFF.md「Authentication」），因此改为要求 `Authorization: Bearer <Supabase access token>`，服务端用 `auth.getUser(token)` 向 Supabase 验证，并按用户 id 做内存限流（10 分钟 12 次，进程内、非分布式，见 AUDIT.md #4）。iOS 调用这两个端点时需要携带自己 session 的 access token，方式与 Web 端一致，可直接复用。`ingest.js`/`activity-ingest.js` 也已修复越权写入问题：两者仍只验证共享静态 Bearer Token（没有浏览器 session，专供 iPhone 快捷指令/脚本使用，设计如此），但写入目标账号现在只来自服务端环境变量，不再信任请求体里的 `userId`/`userEmail`。iOS **仍不应该**直接调用 ingest 类端点或复用其共享 token 鉴权模式——那是为无 session 的自动化场景设计的，不是通用多用户认证方案。 |
| 需要新增的服务端校验 | 1) ~~给 `analyze-meal.js`/`analyze-body.js` 加 Supabase JWT 校验~~ **已完成**（`fix/pre-public-security` 分支）；2) ~~加基础速率限制~~ **已完成**（进程内限流，非分布式，见 AUDIT.md #4 局限说明——iOS 上线后若多实例并发流量增大，应评估换成共享存储的限流方案）；3) 营养数值的合理范围校验（当前仅 `>=0`，无上限，**仍未处理**）。 |
| 日志隐私要求 | 不要在日志/错误信息里回显 `GEMINI_API_KEY`（现状已确认不会，`api/gemini.js` 只把 key 放 query string 发给 Google，不放进返回给客户端的 error）；避免把鉴权 token 放进 URL query string——`api/ingest.js`/`api/activity-ingest.js` 曾支持从 query string 读 `DIARY_INGEST_TOKEN`，**已在 `fix/pre-public-security` 分支修复**：现在只接受 `Authorization: Bearer` header，query 参数（`token`/`diaryToken`/`apiKey`/`key`）一律返回 `400 query_token_not_supported`。iOS 侧新增的任何认证方式都应该从一开始就只用 header，不用 query。 |

## 5. 后端适配结论

**可以直接复用**
- 四张业务表结构 + RLS 策略。
- Supabase Auth（Email OTP）机制本身。
- `meal-photos` Storage 的路径约定与隔离策略（生产库现状）。
- Gemini 识别的 prompt/fallback 逻辑（`api/gemini.js`、`analyze-*.js` 的 `normalizeAnalysis`）。
- `api/_lib/ingestAuth.js` 里的身份绑定模式（服务端配置决定身份、拒绝请求体覆盖、mismatch 返回 403）——如果 iOS 后续需要设计其他无 session 的自动化/服务端到服务端接口，这是一个可参考的最小实现。

**需要小幅调整**
- 给 `analyze-meal.js`/`analyze-body.js` 增加 Supabase JWT 校验，让 iOS/Web 用同一套认证方式调用。
- 把仓库 `supabase/schema.sql` 及相关 fix 文件同步为生产库当前的真实策略（否则新环境初始化会倒退）。
- 补一张 `user_goals`（或类似命名）表，把目标从 `localStorage` 迁移为按用户存储，供 iOS/Web 共享。

**iOS 开发前必须解决**：目前 AUDIT.md 中已没有标记"是否阻塞 iOS：是"的未处理项（全部四条已在 `fix/pre-public-security` 分支修复，见下方"已解决"）。

**已解决**
- `ingest.js`/`activity-ingest.js` 的 `payload.userId`/`userEmail` 覆盖逻辑（AUDIT.md #2）——已在 `fix/pre-public-security` 分支修复，写入目标现在只由服务端配置决定。这两个端点仍不建议 iOS 直接调用（见"可复用能力"表），但已不再构成越权写入风险。
- ingest token 可经 URL query string 传递（AUDIT.md #3）——已在同一分支修复，仅接受 `Authorization: Bearer` header。
- `analyze-meal.js`/`analyze-body.js` 的无鉴权状态（AUDIT.md #4）——已在同一分支修复，要求 Supabase 用户 session + 按用户内存限流。iOS 调用这两个端点时按 Web 端同样的方式携带 access token 即可；进程内限流的分布式局限见 AUDIT.md #4，iOS 上线后若并发量明显增大，建议评估换成共享存储的限流方案。
- 仓库 Storage SQL 与生产库状态不一致（AUDIT.md #1）——已在同一分支修复，`supabase/schema.sql`、`supabase/fix-meal-photos-storage-permissions.sql` 与新增的 `supabase/migrations/` 现在都描述私有 bucket + 按用户隔离的策略，与生产库一致，且已在本地 Docker + Supabase CLI 的一次性非生产实例上完成真实执行验证（全新环境 bootstrap、旧状态升级、跨用户 Storage API 权限行为均通过，详见 AUDIT.md #1）。

**可以后续解决**
- `src/main.tsx`/`styles.css` 拆分——对 iOS 无直接影响（iOS 是独立代码库）。
- 日期/时区统一处理——建议 iOS 新代码从一开始就用 UTC 存储 + 本地时区展示，不需要等 Web 端先改。
- 每日统计的服务端聚合优化——数据量当前较小，非当前阶段瓶颈。

## 6. 推荐路线图

**阶段 0：iOS 项目与安全基线**
验收：项目可编译运行；`SUPABASE_URL`/anon key 走编译期配置且不含任何服务端密钥；在 iOS 团队自己的（非生产）Supabase 项目上实际跑一次 `supabase/schema.sql`（或按顺序应用 `supabase/migrations/` 下的文件），确认 Storage SQL 语法可执行、结果确实是私有 bucket + 按用户隔离（仓库文件已与生产库策略对齐，见 AUDIT.md #1，但尚未做过真实执行验证）。

**阶段 1：Auth**
验收：邮箱 OTP 登录、深链接回跳、session 持久化与自动刷新全部跑通；退出登录后本地无残留可用 session。

**阶段 2：数据模型与数据访问层**
验收：四张表的 Swift model + Repository 落地，含单元测试覆盖 row↔struct 映射；RLS 生效性通过"用两个不同测试账号互相访问不到对方数据"验证。

**阶段 3：今日饮食与记录管理**
验收：手动增删改食物记录跑通；每日汇总计算结果与 Web 端对同一账号同一天数据一致。

**阶段 4：图片与 AI**
验收：拍照/选图上传到正确的用户目录；`/api/analyze-meal`、`/api/analyze-body` 调用携带 iOS 端 Supabase session 的 access token（服务端鉴权已在 `fix/pre-public-security` 分支完成，见 AUDIT.md #4）；AI 结果需用户确认后才写库，与 Web 端规则一致。

**阶段 5：统计与历史**
验收：趋势图表、照片库、历史日历浏览功能对齐 Web 端信息架构（不要求像素级一致）。

**阶段 6：设置、测试与发布准备**
验收：目标设置功能已决定并落地（本地存储 or 新表二选一，非待定状态）；关键路径有 XCTest 覆盖；App Store 发布所需的隐私清单（HealthKit、相机、照片库权限说明）已就绪。
