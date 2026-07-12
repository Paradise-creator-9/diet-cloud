# Diet Cloud iOS（阶段 0 骨架）

原生 iOS App 工程，位于 monorepo 的 `ios/`。与 Web 共用同一 Supabase 项目与 Vercel AI 接口；**不**使用 `DIARY_INGEST_TOKEN` / service role / `GEMINI_API_KEY`。

## 要求

- Xcode 16+（部署目标 iOS 18+）
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)（生成 `.xcodeproj`）

## 生成工程

```bash
cd ios
xcodegen generate
open DietCloud.xcodeproj
```

`DietCloud.xcodeproj` 由 `project.yml` 生成，可提交或不提交；推荐在干净克隆上执行 `xcodegen generate`。

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

**禁止**写入：`SUPABASE_SERVICE_ROLE_KEY`、`GEMINI_API_KEY`、`DIARY_INGEST_TOKEN`。

## 阶段 0 范围

已包含：

- SwiftUI App 入口与占位 `RootView`
- `AppConfig` / xcconfig / Info.plist
- `AppError`、`DiaryCalendar`（与 Web `dateKey` 对齐）
- `SupabaseClientProvider` / `AnalyzeAPIClient` 协议缝（无真实网络调用）
- `AppDependencyContainer` DI
- XCTest：配置、错误映射、日期、DI

**未包含**（后续阶段）：Email OTP、饮食 CRUD、HealthKit、AI 请求、数据库 migration。

## 测试

```bash
cd ios
xcodegen generate
xcodebuild test \
  -project DietCloud.xcodeproj \
  -scheme DietCloud \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=27.0'
```

模拟器名称以本机 `xcrun simctl list devices available` 为准。本机验证过 `iPhone 17 Pro`。

## 与 Web / Shortcuts 边界

- App 数据：用户 Session + RLS。
- AI：`API_BASE_URL` + Bearer access token → 已有 Vercel 接口。
- iPhone 快捷指令 / `activity-ingest`：继续独立运行；**不属于** App 数据层。
