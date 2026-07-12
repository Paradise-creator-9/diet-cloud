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
| `DIETCLOUD_AUTH_REDIRECT_URL` | Magic Link 回 App 的 URL，默认 `dietcloud://auth-callback` | 是（非 secret） |

1. 复制 `Config/Secrets.xcconfig.example` → `Config/Secrets.xcconfig`（已 gitignore）。
2. 填入真实 **公开** 值。
3. 在 `Config/Debug.xcconfig` 中取消 `#include? "Secrets.xcconfig"` 注释。
4. 重新 `xcodegen generate` 并编译。

**禁止**写入：`SUPABASE_SERVICE_ROLE_KEY`、`GEMINI_API_KEY`、`DIARY_INGEST_TOKEN`、access/refresh token。

### Supabase Dashboard（必须手动配置，本仓库不会改生产）

在 **Authentication → URL Configuration → Redirect URLs** 中添加：

```text
dietcloud://auth-callback
```

若缺少该项：

- iOS 发出的 Magic Link **可能回到 Web Site URL**，或被 Supabase 拒绝；
- App 内 `onOpenURL` / `session(from:)` **收不到**登录回调。

验证码（email OTP code）是否出现在邮件中取决于**线上邮件模板**，与本仓库无关；iOS 将其作为**备用**路径。

## 阶段进度

### 阶段 0 — 工程骨架 ✅

### 阶段 1 — Authentication（Magic Link 主路径 + 验证码备用）

**iOS Magic Link 主流程**

1. 用户输入邮箱 → `AuthViewModel.sendOTP`
2. `AuthRepository.sendOTP` → `signInWithOTP(email:redirectTo:)`，`redirectTo` = `DIETCLOUD_AUTH_REDIRECT_URL`（默认 `dietcloud://auth-callback`）
3. 用户在 iPhone 邮件中点击登录链接
4. 系统打开 App（URL scheme `dietcloud`）
5. `RootView.onOpenURL` → `AuthViewModel.handleOpenURL` → `AuthRepository.handleAuthURL` → `auth.session(from:)`
6. 状态 → `signedIn`（Keychain 持久化 session）

**验证码备用**：`verifyOTP` 仅当邮件中实际包含可用 code 时可用。

**Web 对照**：Web 使用 `emailRedirectTo: window.location.origin` + `detectSessionInUrl`（浏览器 Magic Link），无验证码 UI。

Session：`KeychainCredentialStore` + supabase-swift `AuthLocalStorage`（**不用** UserDefaults）。

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
- AI：后续阶段经 `API_BASE_URL`。
- Shortcuts / `activity-ingest`：不属于 App 数据层。
