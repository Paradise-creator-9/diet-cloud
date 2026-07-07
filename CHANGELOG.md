# Changelog

## 0.1.0 - Initial Cloud Version

### Added

- 云端饮食记录应用基础版本。
- Supabase Email Magic Link 登录。
- Supabase Postgres 数据表和 Storage 照片存储。
- 早餐、午餐、晚餐、其他餐次记录。
- 食物明细：重量、热量、蛋白质、碳水、脂肪、膳食纤维、备注和照片。
- 手动新增、编辑、删除饮食记录。
- Gemini 餐食照片分析入口。
- 体重、BMI、体脂、肌肉、水分、基础代谢、内脏脂肪等身体数据记录。
- Gemini 体脂秤截图识别入口。
- 身体数据趋势和身体分布图。
- Apple 健康导出 zip 解析和导入。
- iPhone Shortcuts 运动数据同步 API。
- 运动总览、活动圆环、趋势和健康分类展示。
- 照片库按日期展示餐食图片。
- 常吃食物快捷添加模块。
- 目标系统和减脂复盘建议。
- 响应式桌面端和移动端布局。
- 浅色/深色模式切换。

### Changed

- 从本地静态饮食日记升级为 Vercel + Supabase 云端架构。
- 将照片从本地文件引用迁移为 Supabase Storage 路径。
- 移动端布局改为顶部固定导航和紧凑卡片流。
- 视觉风格向 Apple Health / Apple Fitness 的低饱和、轻量卡片系统靠拢。

### Security

- 真实环境变量不提交，仅保留 `.env.example`。
- service role key 仅用于服务端函数和本地脚本。
- `.gitignore` 排除构建产物、缓存、日志、Vercel 状态和本地环境文件。
