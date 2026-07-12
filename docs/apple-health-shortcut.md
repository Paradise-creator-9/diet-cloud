# iPhone 快捷指令同步 Apple 健康

目标：每天自动把 Apple 健康当天摘要同步到 `https://diet-cloud.vercel.app`。

## 网站接口

- URL: `https://diet-cloud.vercel.app/api/activity-ingest`
- Method: `POST`
- Header:
  - `Authorization`: `Bearer <DIARY_INGEST_TOKEN>`
  - `Content-Type`: `application/json`

## 推荐 JSON

```json
{
  "date": "2026-07-01",
  "source": "apple_shortcut",
  "steps": 8000,
  "activeCalories": 420,
  "totalCalories": 2100,
  "exerciseMinutes": 35,
  "standHours": 10,
  "distanceKm": 5.8,
  "floors": 6,
  "restingHeartRate": 58,
  "hrvMs": 42,
  "sleepMinutes": 430,
  "note": "来自 iPhone 快捷指令自动同步。"
}
```

没有取到的数据可以不传，服务端会按 0 处理。

## 快捷指令动作建议

1. 新建快捷指令：`同步健康数据到饮食记录`。
2. 设置变量 `今天` 为当前日期，格式 `yyyy-MM-dd`。
3. 使用「查找健康样本」分别读取当天数据：
   - 步数
   - 活动能量
   - 锻炼时间
   - 站立时间
   - 步行+跑步距离
   - 爬楼层数
   - 静息心率
   - 心率变异性 HRV
   - 睡眠分析
4. 用「词典」组装上面的 JSON 字段。
5. 用「获取 URL 内容」发送 POST 请求。
6. 在「自动化」里设定每天晚上运行，例如 23:55。

## 注意

- `DIARY_INGEST_TOKEN` 只放在快捷指令和 Vercel 服务端环境变量里，不要写进前端代码。
- Token **只能**放在 `Authorization` Header 里（如上）。旧版本曾允许把 Token 拼进 URL（`?token=...`）当作简化写法，这个方式已停用——带 `token`/`diaryToken`/`apiKey`/`key` 这几个 query 参数的请求会被直接拒绝（`400 query_token_not_supported`），不会再兼容执行。如果你的快捷指令还在用 URL 参数传 Token，请打开「获取 URL 内容」动作，把 URL 里的 `?token=...` 删掉，改成在 Headers 里新增一行 `Authorization` = `Bearer 你的_DIARY_INGEST_TOKEN`。
- 如果快捷指令第一次读取健康数据，iPhone 会要求授权健康权限。
- 同一天重复同步会更新同一天 `apple_shortcut` 来源的数据，不会无限新增。
