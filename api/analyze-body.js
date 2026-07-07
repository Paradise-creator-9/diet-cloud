function json(res, status, payload) {
  res.statusCode = status;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
}

import { generateGeminiContent } from "./gemini.js";

function normalizeError(error) {
  if (error instanceof Error) return { message: error.message, name: error.name };
  if (error && typeof error === "object") return { message: error.message || error.error || JSON.stringify(error), status: error.status };
  return { message: String(error) };
}

async function readJson(req) {
  if (req.body && typeof req.body === "object") return req.body;
  if (typeof req.body === "string") return JSON.parse(req.body);
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const body = Buffer.concat(chunks).toString("utf8");
  return body ? JSON.parse(body) : {};
}

function parseDataUrl(dataUrl) {
  const match = String(dataUrl || "").match(/^data:(.*?);base64,(.+)$/);
  if (!match) throw new Error("截图格式不正确。");
  return { mimeType: match[1] || "image/jpeg", data: match[2] };
}

function extractJson(text) {
  const raw = String(text || "").trim();
  if (!raw) throw new Error("Gemini 没有返回识别结果。");
  try {
    return JSON.parse(raw);
  } catch {
    const match = raw.match(/\{[\s\S]*\}/);
    if (!match) throw new Error("Gemini 返回结果不是 JSON。");
    return JSON.parse(match[0]);
  }
}

function metricNumber(value) {
  if (value === null || value === undefined || value === "") return null;
  const parsed = Number(String(value).replace(/[^\d.-]/g, ""));
  return Number.isFinite(parsed) ? parsed : null;
}

function metricString(value) {
  return value === null || value === undefined ? "" : String(value).trim();
}

function normalizeAnalysis(payload) {
  return {
    confidence: Math.max(0, Math.min(1, Number(payload.confidence || 0.65))),
    date: metricString(payload.date),
    measuredAt: metricString(payload.measuredAt),
    score: metricNumber(payload.score),
    weightKg: metricNumber(payload.weightKg),
    bmi: metricNumber(payload.bmi),
    bodyFatPercent: metricNumber(payload.bodyFatPercent),
    bodyAge: metricNumber(payload.bodyAge),
    bodyType: metricString(payload.bodyType),
    muscleKg: metricNumber(payload.muscleKg),
    skeletalMuscleKg: metricNumber(payload.skeletalMuscleKg),
    boneMassKg: metricNumber(payload.boneMassKg),
    waterPercent: metricNumber(payload.waterPercent),
    visceralFat: metricNumber(payload.visceralFat),
    bmrKcal: metricNumber(payload.bmrKcal),
    proteinPercent: metricNumber(payload.proteinPercent),
    trunkFatPercent: metricNumber(payload.trunkFatPercent),
    trunkMuscleKg: metricNumber(payload.trunkMuscleKg),
    leftArmFatPercent: metricNumber(payload.leftArmFatPercent),
    leftArmMuscleKg: metricNumber(payload.leftArmMuscleKg),
    rightArmFatPercent: metricNumber(payload.rightArmFatPercent),
    rightArmMuscleKg: metricNumber(payload.rightArmMuscleKg),
    leftLegFatPercent: metricNumber(payload.leftLegFatPercent),
    leftLegMuscleKg: metricNumber(payload.leftLegMuscleKg),
    rightLegFatPercent: metricNumber(payload.rightLegFatPercent),
    rightLegMuscleKg: metricNumber(payload.rightLegMuscleKg),
    notes: metricString(payload.notes || "体脂秤截图 OCR 识别结果，请保存前检查。"),
  };
}

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("allow", "POST");
    return json(res, 405, { error: "Method not allowed." });
  }

  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) return json(res, 500, { error: "GEMINI_API_KEY is not configured." });

  try {
    const payload = await readJson(req);
    const screenshot = payload.screenshot || payload.photo;
    if (!screenshot?.dataUrl) return json(res, 400, { error: "请先上传身体数据截图。" });

    const parsed = parseDataUrl(screenshot.dataUrl);
    const prompt = [
      "你是一个严谨的中文体脂秤截图 OCR 助手。请从截图中读取身体数据，并只返回 JSON。",
      "要求：",
      "1. 数值字段只返回数字，不带单位。",
      "2. 没看清或截图没有的字段返回 null，不要猜测。",
      "3. 日期用 YYYY-MM-DD；测量时间用 YYYY-MM-DDTHH:mm，如果截图没有完整时间则返回空字符串。",
      "4. 肢体数据中，蓝色百分比通常是脂肪率，青色数值通常是肌肉量 kg。",
      "5. 字段名必须严格使用下面 JSON 结构。",
      "",
      "JSON 结构：",
      "{",
      '  "confidence": 0.0 到 1.0,',
      '  "date": "YYYY-MM-DD",',
      '  "measuredAt": "YYYY-MM-DDTHH:mm",',
      '  "score": null,',
      '  "weightKg": null,',
      '  "bmi": null,',
      '  "bodyFatPercent": null,',
      '  "bodyAge": null,',
      '  "bodyType": "",',
      '  "muscleKg": null,',
      '  "skeletalMuscleKg": null,',
      '  "boneMassKg": null,',
      '  "waterPercent": null,',
      '  "visceralFat": null,',
      '  "bmrKcal": null,',
      '  "proteinPercent": null,',
      '  "trunkFatPercent": null,',
      '  "trunkMuscleKg": null,',
      '  "leftArmFatPercent": null,',
      '  "leftArmMuscleKg": null,',
      '  "rightArmFatPercent": null,',
      '  "rightArmMuscleKg": null,',
      '  "leftLegFatPercent": null,',
      '  "leftLegMuscleKg": null,',
      '  "rightLegFatPercent": null,',
      '  "rightLegMuscleKg": null,',
      '  "notes": "识别说明"',
      "}",
    ].join("\n");

    const { model, payload: result } = await generateGeminiContent(apiKey, {
      contents: [{
        role: "user",
        parts: [
          { text: prompt },
          { inlineData: { mimeType: screenshot.contentType || parsed.mimeType, data: parsed.data } },
        ],
      }],
      generationConfig: {
        temperature: 0.05,
        responseMimeType: "application/json",
      },
    });

    const text = result.candidates?.[0]?.content?.parts?.map((part) => part.text || "").join("") || "";
    return json(res, 200, { ok: true, model, analysis: normalizeAnalysis(extractJson(text)) });
  } catch (error) {
    const normalized = normalizeError(error);
    return json(res, error.status || 500, { error: normalized.message, details: error.details || normalized });
  }
}
