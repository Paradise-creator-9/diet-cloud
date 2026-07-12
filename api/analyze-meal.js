function json(res, status, payload) {
  res.statusCode = status;
  res.setHeader("content-type", "application/json; charset=utf-8");
  res.end(JSON.stringify(payload));
}

import { generateGeminiContent as realGenerateGeminiContent } from "./gemini.js";
import { requireSupabaseUser, checkRateLimit, respondError, SessionAuthError } from "./_lib/sessionAuth.js";

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
  if (!match) throw new Error("照片格式不正确。");
  return { mimeType: match[1] || "image/jpeg", data: match[2] };
}

function extractJson(text) {
  const raw = String(text || "").trim();
  if (!raw) throw new Error("Gemini 没有返回分析结果。");
  try {
    return JSON.parse(raw);
  } catch {
    const match = raw.match(/\{[\s\S]*\}/);
    if (!match) throw new Error("Gemini 返回结果不是 JSON。");
    return JSON.parse(match[0]);
  }
}

function number(value) {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function normalizeAnalysis(payload) {
  const total = payload.total || {};
  const items = Array.isArray(payload.items) ? payload.items : [];
  return {
    dishName: String(payload.dishName || items.map((item) => item.name).filter(Boolean).slice(0, 3).join("、") || "AI 识别餐食"),
    confidence: Math.max(0, Math.min(1, Number(payload.confidence || 0.6))),
    total: {
      grams: number(total.grams),
      calories: number(total.calories),
      protein: number(total.protein),
      carbs: number(total.carbs),
      fat: number(total.fat),
      fiber: number(total.fiber),
    },
    items: items.map((item) => ({
      name: String(item.name || "未知食物"),
      grams: number(item.grams),
      calories: number(item.calories),
      protein: number(item.protein),
      carbs: number(item.carbs),
      fat: number(item.fat),
      fiber: number(item.fiber),
      reasoning: String(item.reasoning || ""),
    })),
    notes: String(payload.notes || "AI 估算结果，仅供饮食记录参考。"),
  };
}

// `deps` is only ever passed by tests (a stub Supabase client and/or a
// stand-in for generateGeminiContent), so the auth/rate-limit/business
// logic can be exercised without a network call or a real Gemini request.
// Vercel always invokes handler(req, res) with no third argument, so
// production always falls back to the real dependencies below.
export default async function handler(req, res, deps = {}) {
  const generateGeminiContent = deps.generateGeminiContent || realGenerateGeminiContent;
  if (req.method === "OPTIONS") {
    res.setHeader("access-control-allow-methods", "POST, OPTIONS");
    res.setHeader("access-control-allow-headers", "authorization, content-type");
    return json(res, 204, {});
  }

  if (req.method !== "POST") {
    res.setHeader("allow", "POST, OPTIONS");
    return json(res, 405, { error: "Method not allowed.", code: "method_not_allowed" });
  }

  try {
    const user = await requireSupabaseUser(req, deps.supabase);
    checkRateLimit(user.id);

    const apiKey = process.env.GEMINI_API_KEY;
    if (!apiKey) throw new SessionAuthError(500, "GEMINI_API_KEY is not configured.");

    const payload = await readJson(req);
    const photos = Array.isArray(payload.photos) ? payload.photos.slice(0, 3) : [];
    const hint = String(payload.hint || payload.description || payload.note || "").trim();
    if (!photos.length && !hint) throw new SessionAuthError(400, "请上传照片，或者至少填写一句文字说明。");

    const instructions = [
      "要求：",
      "1. 用中文输出。",
      "2. 如果无法确定，请给保守估算，并在 notes 说明不确定因素。",
      "3. total 必须是整顿饭合计。",
      "4. items 尽量按食物拆分，例如米饭、咖喱酱、鸡肉、蔬菜、饮料等。",
      "5. 所有数值使用克或 kcal，不要带单位字符串。",
      "6. 只返回 JSON，不要 Markdown。",
      "",
      "JSON 结构：",
      "{",
      '  "dishName": "简短餐名",',
      '  "confidence": 0.0 到 1.0,',
      '  "total": {"grams": 0, "calories": 0, "protein": 0, "carbs": 0, "fat": 0, "fiber": 0},',
      '  "items": [{"name": "食物名", "grams": 0, "calories": 0, "protein": 0, "carbs": 0, "fat": 0, "fiber": 0, "reasoning": "估算依据"}],',
      '  "notes": "整体说明"',
      "}",
    ].join("\n");

    const prompt = photos.length
      ? [
          "你是一个严谨的饮食营养估算助手。请根据照片估算这顿饭的食物组成、可食重量、热量和营养成分。",
          hint ? `用户补充说明：${hint}` : "",
          hint ? "如果用户的文字说明和照片内容有出入（比如食物种类、数量），以文字说明为准；照片主要用来辅助判断分量和做法。" : "",
          instructions,
        ].filter(Boolean).join("\n")
      : [
          "你是一个严谨的饮食营养估算助手。用户这次没有上传照片，只给了一句文字描述，请完全根据这段文字估算这顿饭的食物组成、可食重量、热量和营养成分。",
          `用户描述：${hint}`,
          "没有照片可参考时，请按常见的家常份量估算，如果描述模糊（比如没写数量、大小），confidence 应该明显偏低，并在 notes 里说明是纯文字估算、建议用户核对份量。",
          instructions,
        ].join("\n");

    const parts = [{ text: prompt }];
    for (const photo of photos) {
      const parsed = parseDataUrl(photo.dataUrl);
      parts.push({ inlineData: { mimeType: photo.contentType || parsed.mimeType, data: parsed.data } });
    }

    const { model, payload: result } = await generateGeminiContent(apiKey, {
      contents: [{ role: "user", parts }],
      generationConfig: {
        temperature: 0.15,
        responseMimeType: "application/json",
      },
    });

    const text = result.candidates?.[0]?.content?.parts?.map((part) => part.text || "").join("") || "";
    return json(res, 200, { ok: true, model, analysis: normalizeAnalysis(extractJson(text)) });
  } catch (error) {
    return respondError(res, error, "analyze-meal");
  }
}
