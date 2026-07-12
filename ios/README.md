# Diet Cloud iOS

原生 iOS App 工程，位于 monorepo 的 `ios/`。与 Web 共用同一 Supabase 项目与 Vercel AI 接口；**不**使用 `DIARY_INGEST_TOKEN` / service role / `GEMINI_API_KEY`。

## 要求

- Xcode 16+（部署目标 iOS 18+）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- 网络解析 [supabase-swift](https://github.com/supabase/supabase-swift)（SPM，首次 `xcodegen` / 构建时下载）

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

- App 入口、AppConfig、DI、AppError、DiaryCalendar、测试 target

### 阶段 1 — Authentication ✅

- Email OTP：发送邮件 → 输入验证码 → 登录（与 Web `signInWithOtp` 同一 Auth 方式）
- Session 恢复（Keychain 经 supabase-swift `AuthLocalStorage`）
- 登出、登录态路由、错误消毒（不泄露 token）
- 可选 URL scheme `dietcloud://` 处理 Magic Link 回跳（若在 Supabase Redirect URLs 中放行）

**未包含**：饮食 CRUD、HealthKit、AI、数据库变更。

### Web vs iOS 登录差异（设计说明）

| | Web | iOS（阶段 1） |
| --- | --- | --- |
| 发起 | `signInWithOtp({ email, emailRedirectTo: origin })` | `signInWithOTP(email:)`（不传未登记 redirect，避免改 Auth 配置） |
| 完成 | 用户点邮件 Magic Link，浏览器 `detectSessionInUrl` | 用户输入邮件中的 **OTP 验证码** `verifyOTP`；可选 Magic Link 深链接 |
| Session | JS SDK localStorage | Keychain（`KeychainCredentialStore` + `SupabaseAuthLocalStorage`） |

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

测试使用 mock repository / in-memory store，**不连接生产 Supabase**。

## 与 Web / Shortcuts 边界

- App 数据：用户 Session + RLS。
- AI：`API_BASE_URL` + Bearer access token → 已有 Vercel 接口（阶段 4）。
- iPhone 快捷指令 / `activity-ingest`：**不属于** App 数据层。
