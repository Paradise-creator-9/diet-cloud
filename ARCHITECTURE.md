# Architecture

## 总览

Diet Cloud 由一个 React 单页应用和数个 Vercel API 端点组成。前端负责登录、展示、表单、图表和文件导入；服务端函数负责需要密钥的 AI 分析、跨账号写入和 iPhone Shortcuts 同步。

```text
Browser / Mobile Safari
  |
  | VITE_SUPABASE_URL + VITE_SUPABASE_ANON_KEY
  v
Supabase Auth + Postgres + Storage
  ^
  |
Vercel Functions
  |-- Gemini API
  |-- Supabase service role
  |-- iPhone Shortcuts Bearer Token
```

## 前端代码结构

### `src/main.tsx`

应用主体文件，包含：

- 顶层状态管理和数据加载。
- 登录、日期选择、视图切换。
- 总览、明细、趋势、照片、身体、运动页面。
- 饮食、身体、运动的新增和编辑对话框。
- 手机端专用布局和桌面端布局。
- 本地计算逻辑：每日汇总、趋势、复盘建议、目标差值。

该文件较大，是后续重构的首要候选。建议按模块拆分到 `components/` 和 `features/`。

### `src/styles.css`

包含主要视觉系统、响应式规则、深色模式、动画和移动端修正。当前样式量较大，后续应按模块拆分或引入 design tokens。

### `src/supabase.ts`

Supabase 数据访问层，负责：

- Auth 登录和登出。
- 读取食物、身体、运动和训练记录。
- 创建、更新、删除饮食记录。
- 上传和删除照片。
- Apple 健康导入数据批量写入。

### `src/appleHealth.ts`

解析 Apple 健康导出的 `export.xml` 和 zip 文件，生成每日活动数据和训练记录。

### `src/types.ts`

定义核心业务类型：

- `FoodItem`
- `BodyMetric`
- `DailyActivity`
- `ExerciseActivity`
- `DailyTotals`

## API 端点

### `api/analyze-meal.js`

接收餐食照片和可选文字说明，调用 Gemini 估算食物明细、重量、热量和营养成分。

### `api/analyze-body.js`

接收体脂秤截图，调用 Gemini 提取体重、体脂、BMI、肌肉量、水分、分段数据等指标。

### `api/gemini.js`

封装 Gemini 调用和模型 fallback。优先使用环境变量指定模型，否则按默认列表尝试。

### `api/ingest.js`

服务端饮食写入接口。用于 Codex 或自动化脚本把结构化饮食记录直接写入 Supabase。使用 `DIARY_INGEST_TOKEN` 验证 Bearer Token。

### `api/activity-ingest.js`

iPhone Shortcuts / 自动化运动数据写入接口。接收 Apple 健康每日指标和训练记录，使用 service role 写入。

## 数据流

### 普通网页读写

1. 用户通过 Supabase Email Magic Link 登录。
2. 前端使用 anon key 调用 Supabase。
3. RLS 根据当前 `auth.uid()` 限制数据访问。
4. 图片上传到 Storage，并在 `food_items.photo_urls` 中保存路径。

### AI 餐食分析

1. 用户上传照片并填写可选描述。
2. 前端把图片 data URL 发给 `/api/analyze-meal`。
3. Vercel Function 使用 `GEMINI_API_KEY` 调用 Gemini。
4. 返回结构化估算结果。
5. 用户确认或修改后保存到 Supabase。

### 身体数据截图识别

1. 用户在身体数据表单上传截图。
2. `/api/analyze-body` 提取数字指标。
3. 前端填充表单。
4. 用户确认后 upsert 到 `body_metrics`。

### Apple 健康导入

1. 用户从 iPhone 健康 App 导出 zip。
2. 前端 Worker 解析导出文件，避免阻塞主线程。
3. 前端调用 `importExerciseData` 批量写入 Supabase。

### iPhone Shortcuts 同步

1. 快捷指令读取当天健康样本。
2. 通过 POST 请求发送到 `/api/activity-ingest`。
3. 接口验证 Bearer Token。
4. 使用 service role 写入 `daily_activities` 和 `exercise_activities`。

## Supabase 表

主要 schema 在 `supabase/schema.sql` 中：

- `food_items`
- `body_metrics`
- `daily_activities`
- `exercise_activities`
- `meal-photos` Storage bucket

补充 SQL 文件用于修复旧环境的权限、约束和 Storage policy。

## 需要优先重构的区域

- 拆分 `src/main.tsx`。
- 拆分 `src/styles.css`。
- 把图表组件独立出来。
- 给 API 返回值增加共享类型和运行时校验。
- 增加端到端或组件级回归测试。
