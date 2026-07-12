# Diet Cloud iOS

原生 iOS App 工程，位于 monorepo 的 `ios/`。与 Web 共用同一 Supabase 项目与 Vercel AI 接口；**不**使用 `DIARY_INGEST_TOKEN` / service role / `GEMINI_API_KEY`。

## 要求

- Xcode 16+（部署目标 iOS 18+）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- SPM：[supabase-swift](https://github.com/supabase/supabase-swift)

## 生成工程

```bash
cd ios
xcodegen generate
open DietCloud.xcodeproj
```

## 配置（仅公开客户端值）

| 键 | 含义 | 是否可公开 |
| --- | --- | --- |
| `SUPABASE_URL` | Supabase 项目 URL | 是 |
| `SUPABASE_ANON_KEY` | anon / publishable key | 是（受 RLS 保护） |
| `API_BASE_URL` | Vercel 源站，用于 `/api/analyze-*` | 是 |
| `STORAGE_BUCKET` | 默认 `meal-photos` | 是 |

1. 复制 `Config/Secrets.xcconfig.example` → `Config/Secrets.xcconfig`（已 gitignore）。
2. 填入真实 **公开** 值。
3. 在 `Config/Debug.xcconfig` 中取消 `#include? "Secrets.xcconfig"` 注释。
4. 重新 `xcodegen generate` 并编译。

**禁止**写入：`SUPABASE_SERVICE_ROLE_KEY`、`GEMINI_API_KEY`、`DIARY_INGEST_TOKEN`、access/refresh token。

## 阶段进度

### 阶段 0 — 工程骨架 ✅

App 入口、AppConfig、DI、AppError、DiaryCalendar、测试 target。

### 阶段 1 — Authentication（基础能力已合入分支；**生产登录需人工验证**）

- 发送邮箱登录邮件（`signInWithOTP`）
- Session 恢复（Keychain via `AuthLocalStorage`）
- 登出、登录态路由、错误消毒
- **可选**验证码路径：`verifyOTP`（仅当邮件模板包含可用 token/code）
- **代码支持** Magic Link deep link：`dietcloud://` + `auth.session(from:)`（见下文限制）

**未包含**：饮食 CRUD、HealthKit、AI、数据库变更。

## Web vs iOS 登录（以仓库代码为准，勿假设邮件内容）

### Web（主要依赖 Magic Link）

| 步骤 | 代码位置 |
| --- | --- |
| 客户端配置 `detectSessionInUrl: true` | `src/supabase.ts` → `createClient` auth options |
| 发起登录 | `src/supabase.ts` → `signInWithEmail` → `auth.signInWithOtp`，`emailRedirectTo: window.location.origin` |
| UI 文案「请打开邮箱里的链接」 | `src/main.tsx` → `AuthGate.handleSubmit` |
| Session 落地 | Magic Link 回到站点后，SDK 从 URL 解析 session（`detectSessionInUrl`）；`main.tsx` 通过 `onAuthChange` 收到 `session.user` |

Web **没有**验证码输入 UI。

### iOS（邮件登录；完成方式取决于模板与 Redirect 配置）

| 步骤 | 代码位置 |
| --- | --- |
| 发起 | `AuthRepository.sendOTP` → `client.auth.signInWithOTP(email:)`（**不传** `redirectTo`） |
| 可选：验证码 | `AuthRepository.verifyOTP` → `client.auth.verifyOTP(email:token:type: .email)` |
| 可选：deep link | `RootView.onOpenURL` → `AuthViewModel.handleOpenURL` → `AuthRepository.handleAuthURL` → `client.auth.session(from:)` |
| URL scheme 声明 | `Info.plist` → `CFBundleURLSchemes` = `dietcloud` |

### 兼容性说明（重要）

1. **仓库无法确认**生产 Supabase 邮件模板是否展示 6 位验证码（无模板 SQL/JSON 在仓内）。
2. 若用户**只收到 Magic Link、没有验证码**：当前 iOS 主界面**不能保证**完成登录——验证码字段无码可用；Magic Link 默认指向 Web 的 `emailRedirectTo` 语义，iOS **发送时未设置** `redirectTo: dietcloud://…`。
3. `dietcloud://` deep link **要真正可用**，必须在 Supabase Dashboard → Auth → Redirect URLs **手动**加入对应 URL，并且发送 OTP 时传入匹配的 `redirectTo`。本仓库**未**修改生产 Auth 配置；因此 deep link 仅为**代码支持**，**不代表生产已可用**。
4. 在生产配置与真机邮件确认前，**真实 iOS 登录仍需人工验证**。
5. 准确描述：iOS 是 **「邮箱登录邮件，支持 Magic Link / Code 取决于 Supabase 邮件模板与 Redirect 配置」**，而不是「保证验证码主流程」。

## 测试

```bash
cd ios
xcodegen generate
xcodebuild test \
  -project DietCloud.xcodeproj \
  -scheme DietCloud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0' \
  -only-testing:DietCloudTests
```

测试使用 mock / in-memory store，**不连接生产 Supabase**。

## 与 Web / Shortcuts 边界

- App 数据：用户 Session + RLS。
- AI：`API_BASE_URL` + Bearer access token → Vercel（后续阶段）。
- Shortcuts / `activity-ingest`：**不属于** App 数据层。
