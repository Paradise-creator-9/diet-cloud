# AUDIT — 膳食志 / Diet Cloud 安全与质量审计

> 只记录有实际代码/配置依据的问题；每条已核实是否影响生产环境（通过 Supabase MCP 只读查询生产项目核实数据库/Storage 实际状态，未做任何写操作；本文档不记录生产项目 ID、完整生产 URL 或任何密钥/Token 的真实值）。排序按风险等级。
>
> **复查说明**：本文档已在同步 `origin/main`（`a1038b9` → fast-forward → `ec396b9`，新增 13 个提交）后基于最新代码与生产库重新核实一次。这 13 个提交只改动了 `src/main.tsx`、`src/styles.css`、`api/analyze-meal.js`、`src/supabase.ts`、`.gitignore`，**未触碰 `supabase/`、`api/ingest.js`、`api/activity-ingest.js`、`api/analyze-body.js`、`api/gemini.js`**（已用 `git diff --stat` 逐一确认为空 diff），生产库 Storage/RLS/迁移记录也已重新查询、与首次检查结果完全一致。因此下列除 #4（AI 端点）、#9（硬编码日期分支）外的条目结论均未改变，逐条已在正文标注"复查"字样。
>
> **修复说明（`fix/pre-public-security` 分支）**：#1（仓库 Storage SQL 与生产库不一致）、#2（ingest 端点身份冒用/越权写入）、#3（ingest token 可经 URL query string 传递）、#4（Gemini 端点无鉴权）均已修复，见各条内"修复状态"。四项修复均只改动了仓库文件（SQL 脚本、migration 文件、API 代码、文档、测试），本轮对生产 Supabase 项目只做过只读查询，从未执行写操作或应用任何 migration。

---

```
风险等级：高（已修复，见下方"修复状态"）
位置（修复前）：supabase/schema.sql、supabase/fix-meal-photos-storage-permissions.sql（全文件）
问题：仓库里的 SQL 把 meal-photos bucket 声明为 public:true，并附一条无用户范围限制的 meal_photos_public_read 读策略。生产库实际状态（MCP 只读核实）是 public:false + 按 auth.uid() 目录隔离的 meal_photos_read_own 读策略，对应生产项目 migration 历史里独立存在的一条记录（`20260708041749_restrict_meal_photos_read_to_owner`），但仓库当时没有 `supabase/migrations/` 目录，这条 migration 只存在于生产项目的 tracked history 里，没有同步回仓库。
影响：生产环境当时是安全的，但仓库不是生产库的可靠"还原蓝图"。任何人（包括未来给 iOS 开发新建测试/预发环境）依照 README 指示"在 SQL Editor 中运行 supabase/schema.sql"来初始化项目，都会重新引入全网可公开读取任意用户餐食照片的漏洞。
修复状态：**已在 `fix/pre-public-security` 分支修复**（提交见该分支 commit，未合并入 main）。修复方式：
- 只读核实生产状态未变：bucket 仍为 `public:false`；`storage.objects` 上与 meal-photos 相关的 4 条策略（`meal_photos_read_own` SELECT、`meal_photos_authenticated_insert_own` INSERT、`meal_photos_authenticated_update_own` UPDATE、`meal_photos_authenticated_delete_own` DELETE）均按 `(storage.foldername(name))[1] = (select auth.uid())::text` 隔离；insert/update/delete 三条策略在仓库里本来就是正确的，只有 bucket 的 `public` 标志和 SELECT 策略与生产不一致。
- `supabase/schema.sql`、`supabase/fix-meal-photos-storage-permissions.sql` 的 bucket insert 语句已改为 `public = false`，SELECT 策略已从无范围限制的 `meal_photos_public_read` 改为按用户目录隔离的 `meal_photos_read_own`（措辞与生产库策略逐字一致）。
- 新增 `supabase/migrations/` 目录（此前不存在），含两个文件：`20260708041749_restrict_meal_photos_read_to_owner.sql` 是**从生产项目 `supabase_migrations.schema_migrations` 表只读查询出的逐字原文**（非重建/猜测），恢复的是当年那条只存在于生产、未同步回仓库的 migration；`20260712000000_set_meal_photos_bucket_private.sql` 是本次新写的后续 migration，专门补上"bucket 的 `public=false` 从未被任何 migration 记录过"这个缺口（该标志很可能是通过 Supabase Studio 手动切换的，不在 SQL 历史里）——对生产库是幂等空操作，对全新项目能确保 bucket 从一开始就是私有的。
- 已用 `node --test`（新增 `supabase/storage-policy.test.mjs`，14 个用例）做静态回归：canonical schema 不再声明 bucket 公开、不存在无范围限制的读策略、不存在 `USING (true)`/`WITH CHECK (true)`、四条 owner 策略都基于 `auth.uid()` 目录隔离、两份 SQL 文件互相不再漂移、两份 migration 文件内容与预期一致。这些测试只读取仓库文件做文本/正则匹配，不连接数据库、不执行 SQL，不能单独证明 SQL 一定能在真实 Postgres 里无错执行。
- **真实执行验证（2026-07-12，本地 Docker + Supabase CLI，非生产、已在验证后完全销毁）**：在全新本地 Supabase 实例上实际执行 `schema.sql`，零错误（仅有 `IF EXISTS`/`IF NOT EXISTS` 产生的预期 NOTICE）；查询真实数据库确认 `meal-photos` bucket `public=false`、`file_size_limit=10485760`、MIME 限制与仓库声明一致，`storage.objects` 上确实存在 4 条 `authenticated`-only、按 `auth.uid()` 目录隔离的策略，且 `meal_photos_public_read`／`USING(true)`／`WITH CHECK(true)` 均不存在。另在一个模拟旧公开状态（公开 bucket + 无范围限制读策略 + 1 条占位对象）的本地实例上按顺序实际执行两个 migration：升级后 bucket 变为私有、旧策略被删除、新 owner-only SELECT 策略建立、insert/update/delete 策略不受影响、占位对象未被删除。两个 migration 的重复执行行为也做了真实测试：`20260712000000_set_meal_photos_bucket_private.sql` 确认幂等（可安全重复执行）；`20260708041749_restrict_meal_photos_read_to_owner.sql`（逐字恢复的历史 migration）确认**不是**幂等的——第二次执行会在 `create policy "meal_photos_read_own"` 处报错「policy already exists」，但失败是非破坏性的（第一次执行建立的正确状态原样保留），这与其"只应通过 Supabase CLI migration 系统应用一次"的定位相符，已在该 migration 文件的注释里补充说明。
- **跨用户 Storage API 权限行为验证**：在同一本地实例上创建两个纯测试账号（`.test` 保留域名，非真实邮箱），通过真实签发的 Supabase session token 调用 Storage REST API，14/14 项检查全部通过：自己上传/读取/更新/删除自己目录下的对象均成功；跨用户读取、上传进对方目录、更新对方对象、删除对方对象均被拒绝；未认证请求读取私有对象被拒绝；`storage/v1/object/public/...` 公开 URL 端点对私有 bucket 同样被拒绝；用户为自己的对象生成签名 URL 成功，为对方对象生成签名 URL 被拒绝。
- 本轮**没有对生产环境执行任何写操作**，只做了只读查询核实；也没有执行任何仓库里的新 migration。
是否阻塞 iOS：否（已修复；新环境执行 `supabase/schema.sql` 或 `supabase/migrations/` 现在会直接得到私有 + 按用户隔离的正确状态）
```

```
风险等级：高（已修复，见下方"修复状态"）
位置（修复前）：api/ingest.js（resolveUserId）、api/activity-ingest.js（resolveUserId，同名同逻辑）
问题：两个 service-role 直写端点在解析目标用户时，优先信任请求体里客户端传入的 userId/userEmail 字段，只有请求体未提供时才回退到服务端配置的 DIARY_USER_ID/DIARY_USER_EMAIL。由于这两个端点用 service-role key 建的 Supabase client 完全绕过 RLS，任何持有共享的 DIARY_INGEST_TOKEN 的调用方都可以让写入目标脱离服务端配置的账号，属于明确的越权写入（IDOR）设计缺陷。
影响：当前项目是单用户个人项目，实际被利用的场景有限（token 本人持有），但一旦 token 泄露或项目扩展为多调用方共享凭证，风险会放大为"任意目标账号数据可被篡改"。
复查：同步 origin/main 到 ec396b9 后确认两个文件在该次同步中完全未变化，问题在复查时点仍然存在。
修复状态：**已在 `fix/pre-public-security` 分支修复**（提交见该分支 commit，未合并入 main）。修复方式：新增 `api/_lib/ingestAuth.js` 共享模块，`resolveTrustedUserId()` 现在只信任服务端环境变量 DIARY_USER_ID/DIARY_USER_EMAIL 来决定写入目标；请求体里的 userId/userEmail 字段不再具有身份决定作用，若其值与服务端解析出的账号不一致，直接以 403 拒绝并记录一条不含敏感信息的日志，而不是静默按请求体执行。`api/ingest.js`、`api/activity-ingest.js` 均已改为调用该共享函数。已用 `node --test`（`api/_lib/ingestAuth.test.mjs`、`api/ingest.test.mjs`、`api/activity-ingest.test.mjs`）验证：认证缺失/无效返回 401，身份不匹配返回 403 且不触发任何数据库调用，必填字段缺失返回 400，方法不支持返回 405。
残余风险：这两个端点仍然只用共享静态 Bearer Token 认证——原因见 HANDOFF.md「Authentication」章节"为什么 ingest 端点仍用 service-role"一节；Token 经 URL query string 传递的问题已在同一分支的后续 commit 修复（见 #3）；上传路径中的日期字段格式校验缺口（见 #8）仍未在本轮处理。
是否阻塞 iOS：否（已修复；iOS 仍不建议直接调用这两个端点，应走 Supabase 客户端 SDK + RLS，见 IOS_GUIDE.md）
```

```
风险等级：中（已修复，见下方"修复状态"）
位置（修复前）：api/_lib/ingestAuth.js 的 `requireIngestToken()`（被 `api/ingest.js`、`api/activity-ingest.js` 共用），token 除标准 `Authorization: Bearer` header 外，还接受 URL query 参数（`token`/`diaryToken`/`apiKey`/`key`）和自定义 `x-diary-token` header。
问题：DIARY_INGEST_TOKEN 除标准 Authorization Header 外还允许通过 URL query string 传递。Query string 会被边缘节点、代理、访问日志等处以明文记录。
影响：Token 通过日志泄露的概率显著高于纯 header 方案；上一条 IDOR 问题已修复，但 Token 本身一旦泄露仍可用于对配置账号的写入操作。
修复状态：**已在 `fix/pre-public-security` 分支修复**（提交见该分支 commit，未合并入 main）。修复方式：
- `requireIngestToken()` 现在**只**接受标准 `Authorization: Bearer <token>` header；已移除 query 参数（`token`/`diaryToken`/`apiKey`/`key`）与自定义 `x-diary-token` header 两条兼容路径。
- 请求 URL 中只要出现上述任一 query 参数名，无论其值是否正确、无论 Authorization header 是否同时存在，一律返回 `400 query_token_not_supported`，不再静默忽略或兼容执行——强制调用方把 Token 从 URL 里彻底清除，而不是继续用一个已经泄露风险更高的旧参数当"顺便也行"的备选项。
- token 比较从普通字符串 `!==` 改为 `node:crypto` 的 `timingSafeEqual`（长度不同时先与等长零值比较避免直接抛错/短路，再返回 false），避免逐字符时间侧信道；`DIARY_INGEST_TOKEN` 未配置时仍安全返回 500，不参与比较。
- 已更新 `src/main.tsx` 内 iPhone 快捷指令说明文字与 `docs/apple-health-shortcut.md`，移除 URL 参数法的推荐、改为要求 Header 传参，并提示用户手动清理已配置的旧快捷指令。
- 已用 `node --test` 新增/扩展用例验证：仅 header 认证通过；仅 query token（无 header）→ 400 `query_token_not_supported`；header 正确但仍带 query token → 照样拒绝；不同 query 参数别名（`diaryToken`/`apiKey`/`key`）逐一验证；无关业务 query 参数不误伤；不同长度/错误 token 比较不抛异常；错误响应正文不回显 token 真实值。
是否阻塞 iOS：否（已修复；iOS 若复用类似的共享 token 模式，应直接照抄新的 header-only 实现）
```

```
风险等级：中（已修复，见下方"修复状态"）
位置（修复前）：api/analyze-meal.js、api/analyze-body.js（全文件，均无鉴权中间件）
问题：两个调用 Gemini 的端点没有任何身份校验或速率限制，任何知道 URL 的人都可以直接调用，消耗项目的 GEMINI_API_KEY 额度/费用；`api/analyze-meal.js` 还支持纯文字（无照片）分析，构造成本比图片模式更低。
影响：成本滥用/拒绝服务风险；由于没有请求方身份记录，也无法追责或按用户限流。
修复状态：**已在 `fix/pre-public-security` 分支修复**（提交见该分支 commit，未合并入 main）。修复方式：
- 全仓库搜索确认 `api/analyze-meal.js`/`api/analyze-body.js` 的唯一调用方是 `src/main.tsx` 里登录后才会渲染的表单组件（应用顶层在 `userEmail` 为空时直接 `return <AuthGate mode="login" />`，未登录用户根本拿不到能发起这两个请求的 UI），确认这两个端点确实运行在网页登录 session 场景下，因此改用 Supabase 用户 JWT 校验是合适的方案（与 ingest 端点的无 session 场景不同）。
- 新增 `api/_lib/sessionAuth.js`：`requireSupabaseUser()` 读取 `Authorization: Bearer <access_token>`，用 Supabase anon key 客户端调用 `auth.getUser(token)` 向 Supabase Auth 服务器验证（而非本地解码 JWT），缺失/无效/过期均返回 401。
- 新增按已验证用户 id 计数的进程内内存限流（`checkRateLimit()`，窗口 10 分钟、上限 12 次/用户），超限返回 429 + `Retry-After`。**已知局限**：仅单实例内存计数，Vercel 可能并发多个实例/冷启动无共享内存，无法防御分布式或跨实例滥用，只能提高单一浏览器标签页/脚本连续刷同一实例的门槛。
- `src/supabase.ts` 新增 `getAccessToken()`；`src/main.tsx` 的两处 `fetch("/api/analyze-meal"/"/api/analyze-body")` 均已改为附带当前 session 的 `Authorization: Bearer` header，token 为空时直接抛出清晰错误（复用既有 `setError`/`formatCloudError` 展示路径），不再静默发起未授权请求。
- 已用 `node --test`（`api/_lib/sessionAuth.test.mjs`、`api/analyze-meal.test.mjs`、`api/analyze-body.test.mjs`）验证：无/无效/过期 token 返回 401 且不消耗 Gemini 调用；已认证用户可进入业务逻辑（用注入的 Supabase client 桩验证，未发起真实 Gemini 请求）；超过限流阈值返回 429 而非 500；不支持的方法返回 405；图片模式与纯文字模式共用同一鉴权/限流网关。
残余风险：进程内限流的分布式局限（见上）；未做全局/账号级别的 Gemini 总额度硬上限（例如按天/按月封顶）；`GEMINI_API_KEY` 本身若泄露仍可被直接用于调用 Google API（与本次修复的授权层无关，是密钥保管问题）。
是否阻塞 iOS：否（已修复；iOS 调用这两个端点时需携带 Supabase 用户 access token，与 Web 端一致）
```

```
风险等级：低
位置：src/main.tsx（本地 dateKey()，基于浏览器 Date）vs api/activity-ingest.js（todayKey()，硬编码 Intl.DateTimeFormat timeZone: "Asia/Tokyo"）
问题：前端"今天"的计算完全依赖浏览器本地时区，没有 UTC 转换；服务端 ingest 端点在请求未显式传 date 字段时，用硬编码的 Asia/Tokyo 时区兜底计算"今天"。appleHealth.ts 的日期分桶（dateKeyFromAppleDate）也只是对 Apple 导出字符串做前 10 位字符截取，直接继承 Apple 健康导出文件里写的时区。
影响：如果用户所在时区与 Asia/Tokyo 不同，或者在时区间旅行，深夜时段（例如 23:00-01:00）通过 iPhone 快捷指令自动同步的运动数据可能被记到"错误的一天"，且和网页端手动查看的"今天"不一致。当前无法确认这是有意为之（用户可能确实固定在东京时区生活）还是遗留假设。
建议：与用户确认实际使用时区是否固定；长期建议统一改为"以用户设置的时区为准"而非硬编码，iOS 端新代码建议直接用 UTC 存储 + 客户端本地时区展示，避免引入新的不一致源。
是否阻塞 iOS：否（不阻塞，但建议 iOS 新代码从一开始就避免这个模式）
复查：`api/activity-ingest.js` 与 `src/appleHealth.ts` 本次同步均未变化，问题原样存在。
```

```
风险等级：低
位置：src/main.tsx 内 UserGoals 状态（localStorage key 形如 diet-cloud-goals-v1），无对应 Supabase 表
问题：用户目标（每日热量/蛋白/纤维、目标体重等）只存在浏览器 localStorage，没有持久化到 Supabase，不跨设备/浏览器同步。
影响：非安全问题，但是数据完整性/一致性缺口——换设备或清浏览器缓存会丢失目标设置；iOS 与 Web 之间目标数据完全隔离。
建议：新增一张按 user_id 隔离的 user_goals 表（结构类似 body_metrics 的单行/多行设计），Web 和 iOS 共用。
是否阻塞 iOS：否（iOS 可以先做本地存储起步，但会与 Web 数据不互通，建议列入路线图较早阶段）
复查：同步后的 src/main.tsx 里 UserGoals 仍只读写 window.localStorage（key 不变，仍是 diet-cloud-goals-v1），src/supabase.ts 未新增任何 goal 相关函数，问题原样存在。
```

```
风险等级：低
位置：supabase/body-metrics.sql、supabase/exercise.sql 与 supabase/schema.sql 重复定义 body_metrics/daily_activities/exercise_activities 表结构与 RLS 策略
问题：同一张表的 DDL 分散在两个独立文件里维护（均为"建表 if not exists + drop/recreate 同名策略"模式），没有单一权威来源。
影响：日后修改任一表结构时容易漏改其中一个文件，导致两份定义静默漂移，增加了新环境初始化时的不确定性（不确定该以哪个文件为准），间接加重了第一条"仓库 SQL 与生产库不一致"问题的成因。
建议：合并为单一 schema 文件或改用 Supabase CLI migrations 目录做时间序列化管理。
是否阻塞 iOS：否
复查：supabase/ 目录本次同步未变化，问题原样存在。
```

```
风险等级：低
位置：api/ingest.js:94-96（uploadPhotos，storagePath = `${userId}/${date}/${fileName}`）
问题：拼接 Storage 路径时，photo.date 字段直接来自请求体，没有做格式校验（fileName 有 safeStorageName 过滤，date 没有）。
影响：字段格式不受控，理论上存在路径注入风险；由于调用方需要先持有 DIARY_INGEST_TOKEN，实际利用门槛较高，但仍是一个可以简单修复的输入验证缺口。
建议：对 date 字段做 `^\d{4}-\d{2}-\d{2}$` 格式校验，不匹配则拒绝请求。
是否阻塞 iOS：否
复查：api/ingest.js 本次同步未变化，问题原样存在。
```

```
风险等级：低
位置：src/main.tsx:2415（BodyMetricDialog 内 `useScreenshotDefaults = !metric && defaultDate === "2026-06-30"` 分支，同步后行号从原先的 2328 变为 2415）；另在 src/main.tsx:3873（`bodyPartMetrics()` 内 `screenshotDefaults = metric.date === "2026-06-30" ? {...} : null`）发现**同类的第二处**，首轮审计遗漏，本次复查一并补上
问题：存在两段硬编码日期触发的"截图默认值"分支，均看起来是开发期间遗留的测试脚手架：一处在新建身体数据表单里，当 defaultDate 恰好等于 2026-06-30 时静默预填一组特定数值；另一处在 bodyPartMetrics() 里，当某条已保存记录的 date 字段等于 2026-06-30 时，用一组硬编码的分段体脂/肌肉数据替代该记录本身缺失的分段字段。
影响：非安全问题，但是生产代码里的测试遗留逻辑，行为对用户不可见/不可解释。第二处的影响面更具体：任何用户如果真的在 2026-06-30 这一天保存了一条 body_metrics 记录、且当时没有分段数据，查看该记录的身体分布图时会看到这组硬编码数值而非真实缺省值，容易被误认为是真实测量结果。
建议：确认这两处是否还需要，不需要则直接删除；如果 2026-06-30 是用户本人真实用过的一条历史截图数据的日期，建议改为按该条记录的 id 或来源标记判断，而不是用日期字符串做隐式判断。
是否阻塞 iOS：否
```

```
风险等级：低
位置：src/supabase.ts（updateFoodItem 附近对 photo_urls 的 diff 逻辑）与 removeUnreferencedPhotoPaths（428-443）
问题：食物记录更新/删除时的孤儿照片清理逻辑是"先 SELECT 检查引用，再决定是否 DELETE"的非原子操作；updateFoodItem 还存在读取阶段可能拿到并发写入前的旧快照的竞态窗口。
影响：并发编辑同一用户的记录时（例如同一账号在两台设备同时操作），理论上可能出现误删仍被引用的照片、或漏删已成孤儿的照片，导致图片丢失或 Storage 里堆积无用文件。个人单用户场景下触发概率低。
建议：可后续用数据库事务或 Storage 生命周期规则替代客户端"先查再删"的模式；当前风险等级低，不建议为此单独立项优先修复。
是否阻塞 iOS：否
复查：本次同步中 src/supabase.ts 唯一的改动是 onAuthChange 回调签名（登录态修复，见 HANDOFF.md），与 Storage/照片清理逻辑无关，问题原样存在。
```

---

## 未纳入正式清单的观察项（供参考，非独立高价值发现）

- 项目无 ESLint/Prettier/CI/自动化测试——`TODO.md` 已自述并列为"工程质量"待办，非本次审计新发现，故不重复计分。
- `food_items.calories/protein/carbs/fat/fiber/grams` 等数值只有数据库层 `check(>=0)` 下限约束，客户端也只做 `Number.isFinite` 兜底，没有任何上限/合理性校验——AI 识别或手动输入的异常大数值可以直接落库。风险等级低（不构成越权或数据泄露，只影响数据质量），未单列条目，建议在阶段 3/4 顺手加校验。
- Supabase Auth 顾问（get_advisors，security 类型）报告"Leaked Password Protection Disabled"，但项目只用 Email OTP、不涉及密码，该项对本项目实际风险可忽略，仅作记录。
- 本次同步的 13 个提交里，commit `266315e`（"Fix daily photo quota over-counting shared AI-split photos"）修复了 `countPhotosUploadedToday()` 按 `photoUrls.length` 直接求和、导致 AI 拆分一张照片为多个食物时被重复计数的 bug（现改为按去重后的 URL 计数）。这不是一个安全问题，仅作为"代码质量在持续改进"的记录，不构成独立审计条目。
