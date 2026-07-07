# Diet Cloud

Diet Cloud 是一个面向个人减脂复盘的云端饮食、身体和运动记录应用。项目把每日餐食照片、营养估算、体脂秤数据、Apple 健康运动数据和趋势分析集中在一个响应式网页中，支持电脑和手机浏览。

当前版本使用 Vercel 部署前端和服务端函数，Supabase 保存账号、结构化数据和照片，Gemini 用于餐食照片和身体数据截图的辅助识别。

## 技术栈

- React 19
- TypeScript
- Vite
- Supabase Auth / Postgres / Storage
- Vercel Functions
- Gemini API
- fflate，用于解析 Apple 健康导出的 zip
- lucide-react 图标

## 安装方式

```bash
npm install
```

## 启动方式

```bash
npm run dev
```

默认本地地址由 Vite 输出，项目脚本绑定 `127.0.0.1`。

## 构建方式

```bash
npm run build
```

构建产物输出到 `dist/`，该目录不提交到 Git。

## 环境变量

复制 `.env.example` 为 `.env.local` 或在 Vercel Project Settings 中配置同名变量。

| 变量 | 作用 | 暴露范围 |
| --- | --- | --- |
| `VITE_SUPABASE_URL` | 前端连接 Supabase 的项目 URL | 浏览器 |
| `VITE_SUPABASE_ANON_KEY` | Supabase 匿名公钥，用于登录和受 RLS 限制的数据访问 | 浏览器 |
| `VITE_SUPABASE_STORAGE_BUCKET` | 餐食照片 bucket，默认 `meal-photos` | 浏览器 |
| `SUPABASE_URL` | 服务端函数和本地脚本使用的 Supabase URL | 服务端 |
| `SUPABASE_SERVICE_ROLE_KEY` | 服务端写入、导入、Shortcuts 同步使用的 service role key | 服务端，禁止提交 |
| `SUPABASE_STORAGE_BUCKET` | 服务端照片 bucket，默认 `meal-photos` | 服务端 |
| `DIARY_INGEST_TOKEN` | `/api/ingest` 和 `/api/activity-ingest` 的 Bearer Token | 服务端 |
| `DIARY_USER_EMAIL` | 服务端导入时定位目标 Supabase 用户 | 服务端 |
| `DIARY_USER_ID` | 本地历史导入脚本使用的目标用户 UUID | 本地脚本 |
| `GEMINI_API_KEY` | Gemini 图片分析 API Key | 服务端 |
| `GEMINI_MODEL` | 可选，指定单个 Gemini 模型 | 服务端 |
| `GEMINI_MODELS` | 可选，逗号分隔的 Gemini fallback 模型列表 | 服务端 |
| `LOCAL_DIARY_DATA` | 可选，覆盖本地旧饮食记录路径 | 本地脚本 |

真实 `.env`、`.env.local`、`.env.runtime` 和所有 `.env.*` 文件都被 `.gitignore` 排除，仓库只保留 `.env.example`。

## Supabase 初始化

1. 创建 Supabase 项目。
2. 在 SQL Editor 中运行 `supabase/schema.sql`。
3. 如果已有旧环境或权限问题，按需运行 `supabase/fix-*.sql` 文件。
4. 在 Authentication 中启用 Email Magic Link。
5. 确认 Storage bucket `meal-photos` 存在，并按 SQL 策略开放当前账号可写、照片可读。

## Vercel 部署

项目使用 `vercel.json`：

```json
{
  "buildCommand": "npm run build",
  "outputDirectory": "dist",
  "framework": "vite"
}
```

部署前在 Vercel 中配置上面列出的环境变量。前端变量必须以 `VITE_` 开头，service role、Gemini Key 和 ingest token 只能放在服务端环境变量中。

## 常用脚本

```bash
npm run dev
npm run build
npm run preview
npm run import:local
```

`npm run import:local` 会读取旧本地饮食记录并写入 Supabase，需要提供 `SUPABASE_SERVICE_ROLE_KEY` 和 `DIARY_USER_ID`。

## 项目目录结构

```text
diet-cloud/
├── api/                 # Vercel Functions：AI 分析、饮食写入、运动同步
├── design-previews/     # UI 设计预览资产
├── docs/                # 使用说明和外部导入文档
├── pending/             # 待导入的历史记录和照片
├── public/              # 静态资源和已迁移照片
├── scripts/             # 本地导入和接口发送脚本
├── src/                 # React 前端源码
│   ├── appleHealth.ts   # Apple 健康导出解析
│   ├── main.tsx         # 应用主体、页面、表单、图表
│   ├── styles.css       # 响应式和主题样式
│   ├── supabase.ts      # Supabase 数据访问层
│   └── types.ts         # 核心类型
├── supabase/            # 数据库 schema 和权限修复 SQL
├── PROJECT_CONTEXT.md
├── ARCHITECTURE.md
├── TODO.md
└── CHANGELOG.md
```

## 安全注意事项

- 不要提交真实 API Key、Supabase service role key、ingest token 或个人 `.env` 文件。
- `SUPABASE_SERVICE_ROLE_KEY` 只能用于 Vercel 服务端函数或本地一次性脚本。
- 如果要公开仓库，建议先移除 `pending/` 和 `public/photos/` 中的个人餐食照片；如果保留照片，建议使用私有仓库。
