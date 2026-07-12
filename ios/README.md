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
3. `Debug.xcconfig` / `Release.xcconfig` 已 `#include? "Secrets.xcconfig"`。
4. 重新 `xcodegen generate` 并编译。

### xcconfig URL 写法（必读 — 白屏根因）

在 `.xcconfig` 里，`//` **会开启注释**。若写成：

```text
SUPABASE_URL = https://xxx.supabase.co
```

实际进 Info.plist 的值会变成 **`https:`**（后面全被注释掉），App 用无效 URL 初始化 Supabase 时可能卡死/崩溃 → **整屏白屏**。

正确写法（`SLASH` 已在 Base/Secrets 中定义）：

```text
SLASH = /
SUPABASE_URL = https:$(SLASH)$(SLASH)xxxx.supabase.co
API_BASE_URL = https:$(SLASH)$(SLASH)diet-cloud.vercel.app
DIETCLOUD_AUTH_REDIRECT_URL = dietcloud:$(SLASH)$(SLASH)auth-callback
```

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

### 阶段 1 — Authentication（Magic Link 主路径 + 验证码备用）✅

**真机验收（已通过）**：Magic Link 邮件点击可回到 App 并进入 `signedIn`；Session 恢复与登出按设计可用。不记录真实邮箱、用户 ID 或 token。  
前置：Supabase Redirect URLs 已包含 `dietcloud://auth-callback`（Dashboard 手动配置，非本仓库变更）。

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

### 阶段 2 — Models + Repositories（数据层，无正式 UI）✅

与 Web / `supabase/schema.sql` 对齐的领域模型与 Repository（RLS + 用户 Session；无 service-role）。

| Schema 表 | Domain | Repository |
| --- | --- | --- |
| `food_items` | `FoodItem` / `FoodItemWrite` / `MealGroup`（客户端分组，非表） | `FoodItemRepository` + `MockFoodItemRepository` |
| `body_metrics` | `BodyMetric` / `BodyMetricWrite` | `BodyMetricsRepository` |
| `daily_activities` | `DailyActivity` | `DailyActivityRepository` |
| `exercise_activities` | `ExerciseActivity` | `ExerciseActivityRepository` |
| Storage `meal-photos` | `MealPhotoRef` / path helpers | `MealPhotoRepository`（signed URL 接口；无上传 UI） |

**不在当前 schema（未实现表）**：`user_goals`、`favorite_foods`、独立 `meals` 聚合表、`profiles`。

`dateKey`：设备本地日历 `YYYY-MM-DD`（与 Web `main.tsx` `dateKey` 一致）；提供 `DiaryCalendar.tokyo()` 仅供测试/对照 ingest。

### 阶段 3 — 今日饮食 UI ✅

登录后进入 `TodayMealsView`（非 Auth 占位页）：

- 展示今日 `dateKey`、按四餐分组列表、本地营养汇总
- 手动新增食物（名称 / 餐次 / 热量 / 可选营养）
- 左滑删除；**编辑**留到后续（本阶段未做编辑表单）
- 退出登录入口保留在工具栏账号菜单

### 阶段 4 — 餐食照片 Storage 链路 ✅

- 相册选择（PhotosPicker）→ JPEG 压缩 → 上传私有 `meal-photos`
- 路径：`{userId}/{dateKey}/{timestamp}-{fileName}`（userId 仅来自 Session）
- 关联：`food_items.photo_urls` 存 **Storage 路径**（与 Web 一致，字段名历史遗留）
- 列表：`AsyncImage` + **signed URL**（非 public URL）
- 删除食物：尽量清理无引用的 Storage 对象
- **未做**：拍照、多图编辑 UI

### 阶段 5 — 餐食 AI 分析（`/api/analyze-meal`）

- 新增食物表单：文字说明（备注）和/或本地照片 → **AI 分析餐食**
- `AnalyzeAPIClient` → `POST {API_BASE_URL}/api/analyze-meal`
- `Authorization: Bearer <Supabase session access token>`（来自当前登录 Session；不进 URL / 日志）
- **不**内置 `GEMINI_API_KEY`；**不**直连 Gemini
- 请求体与 Web 对齐：`{ photos: [{ fileName, contentType, dataUrl }], hint }`
- 图片：阶段 4 压缩后的 JPEG data URL（不用 signed URL）
- 成功：填入名称/热量/营养/备注；**不自动保存**，用户确认后再写入
- 错误映射：401 / 413 / 429 / 5xx 为安全中文文案
- **未做**：身体截图 AI（`analyze-body`）、HealthKit、多食物拆分编辑 UI

### 阶段 6 — 历史日期浏览 / 补记

- 饮食页顶部：前一天 / 后一天 / 日期标题 /「今天」/ 系统 `DatePicker`
- `selectedDate` + `selectedDateKey`（`DiaryCalendar` 本地 `YYYY-MM-DD`）
- 切换日期后重新 `fetchByDateKey`；汇总与列表仅针对当前日
- 补记：新增食物 / 照片上传 / AI 填表均写入 **当前选中** `dateKey`（非强制今天）
- 照片 path 仍为 `{userId}/{selectedDateKey}/...`；缩略图 signed URL
- 新增 sheet 打开时禁用日期切换（切换会关闭 sheet），避免状态错乱
- **未做**：复杂月历、跨日批量编辑

### 阶段 7 — 身体 / 活动 / 运动 UI（手动，无 HealthKit）

- 跟随 `selectedDate`：身体指标、每日活动、运动列表与饮食同日加载
- 身体：体重 / 可选体脂 / 备注；upsert + 删除（`body_metrics`）
- 每日活动：步数 / 活动热量 / 可选距离；source=`manual` upsert + 删除
- 运动：类型 / 标题 / 时长 / 消耗 / 可选距离；新增 + 左滑删除
- **当日总览**卡片固定在日期栏下方（列表外）：摄入、活动消耗、运动消耗、净热量、步数、体重；无圆环图
- **未做**：身体截图 AI、`/api/analyze-body`、复杂体成分全字段编辑

### 阶段 8 — HealthKit 只读导入

- 入口：「从健康导入」（当日总览下方），仅导入 **当前 selectedDate**
- 只读权限：步数、活动能量、步行跑步距离、体重、体脂%、workout
- **不向 HealthKit 写入**
- 映射：
  - daily_activities（`source=healthkit`）：steps / activeCalories / distanceKm
  - body_metrics：weightKg / bodyFatPercent（无 source 列；有已有体重时需确认覆盖）
  - exercise_activities（`source=healthkit`，`external_id`=workout UUID）：类型/时长/消耗/距离
- 手动数据：有 manual 每日活动或已有体重时**不静默覆盖**，弹窗确认后才更新
- 运动去重：`external_id` 优先；否则 type+startedAt+duration+calories 指纹
- **热量策略（方案 B）**：当每日活动 `source=healthkit` 时，净热量 = 摄入 − 活动消耗（active energy 已含 workout，不重复扣运动列表）；手动每日活动仍扣 活动+运动
- **未做**：后台自动同步、HealthKit 写入、复杂增量同步、身体截图 AI

### 阶段 9 — 目标与设置

- 入口：导航栏齿轮 / 账户菜单 → **设置**
- 本地目标（UserDefaults，不改 schema）：每日热量、目标体重、蛋白/碳水/脂肪
- 当日总览：摄入/净热量/宏量相对目标（`当前 / 目标`）；无目标时仅显示当前值
- 账户：打码邮箱、健康导入说明、退出登录（确认弹窗）
- **未做**：云端同步目标、多用户目标档案

### 阶段 10 — 首页视觉打磨

- 当日总览：摄入 / 净热量圆环 + 蛋白/碳水/脂肪进度条；进度 clamp 在 0…1
- 无目标时圆环仅显示数值、轨道为空，不报错
- 信息层级：总览突出；身体/活动/运动/饮食分区标题与空状态更清晰
- 快捷操作：工具栏「添加」更明显；AI 分析用 prominent 按钮；健康导入改为轻量 bordered
- **未做**：复杂动画、自定义主题系统、第三方 UI 库

### 阶段 11 — 趋势与统计

- 入口：饮食页导航栏「趋势」（`chart.xyaxis.line`）→ `TrendsView`（`navigationDestination`，无 TabView）
- 范围：近 7 天 / 近 30 天（含今天）；`fetchBetween(startDateKey:endDateKey:)` 区间查询（gte/lte，不改 schema）
- 展示：热量柱图（目标参考线）、营养分段（蛋白/碳水/膳食纤维）、体重、活动分段（步数/活动消耗）；Swift Charts
- 摘要：有饮食天数、平均摄入、综合达标天数、运动次数与总时长
- 聚合：同日食物 totals；活动 HealthKit 优先于 manual（不相加）；运动按日求和；体重取最新；平均值仅以有数据天为分母
- 达标：热量 90%–110%；蛋白/纤维 ≥ 目标；碳水仅展示；三项目标皆未设时显示「未设置目标」
- 状态：loading / loaded / partial / empty / error + 重试；retry 保留已展示快照、不全屏清空
- 图表：Swift Charts 按日坐标；30 天横轴稀疏标签；单点靠 PointMark 可见
- **未做**：净热量跨日图、自定义任意区间、Tab 壳、云端目标

### 阶段 12 — 本地提醒与通知

- UserNotifications 本地**每日重复**提醒；**无** APNs / 远程推送 / 云端表
- 设置页「提醒」：早/午/晚饮食、称重、每日总结；开关 + 时间；改后立即保存并重注册
- 默认时间：08:00 / 12:30 / 19:00 / 07:30 / 21:30（默认全关）
- 首次开启任一项时请求 alert+sound；启动不弹权；denied 显示状态 + 前往系统设置
- 稳定 id：`dietcloud.reminder.*`；apply 时只移除这些 id 再注册已开启项
- 存储：UserDefaults `dietcloud.reminderSettings.v1`；`NotificationScheduling` 可 mock
- 前台 active / 设置 onAppear：刷新权限并 reconcile
- **未做**：通知点击深链、智能跳过已记录日、badge、Action 按钮

### 阶段 13 — 编辑饮食记录

- 点击食物行（或左滑「编辑」）打开编辑 sheet；保留左滑删除
- 可改：名称、餐次、日期、份量、备注、热量/蛋白/碳水/脂肪/**膳食纤维**
- `update(id:write:)` 更新原行；**不** create；**保留** `photoPaths` 与 `sourceId`
- 编辑模式隐藏 AI / 换图；原图只读缩略图
- 改日期后不跳转，当前日刷新后该条消失，提示「已保存到 YYYY-MM-DD」
- 新增路径支持 fiber 输入（不再写死 `fiber: 0`）
- 负数/非法数字在 ViewModel 校验，不调用 Repository
- **未做**：换图、编辑时 AI、批量编辑、食物库搜索

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
- AI：经 `API_BASE_URL` + 用户 Session Bearer（阶段 5 餐食分析）。
- Shortcuts / `activity-ingest`：不属于 App 数据层。
