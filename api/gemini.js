const FALLBACK_MODELS = [
  "gemini-3.5-flash",
  "gemini-3.1-flash-lite",
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite",
];

function unique(values) {
  return [...new Set(values.map((value) => String(value || "").trim()).filter(Boolean))];
}

function modelCandidates() {
  const configured = process.env.GEMINI_MODELS || process.env.GEMINI_MODEL || "";
  return unique([...configured.split(","), ...FALLBACK_MODELS]);
}

async function readGeminiPayload(response) {
  const text = await response.text();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch {
    return { raw: text };
  }
}

function errorMessage(payload) {
  return String(payload?.error?.message || payload?.raw || payload?.message || "Gemini request failed.");
}

function isRetryable(status, message) {
  return status === 429 ||
    status === 500 ||
    status === 502 ||
    status === 503 ||
    status === 504 ||
    /high demand|overloaded|temporar|try again later|rate limit|unavailable|busy/i.test(message);
}

function friendlyGeminiError(lastError, errors) {
  const message = errors.map((error) => error.message).join(" ");
  if (/api key|permission|unauthorized|forbidden|invalid key/i.test(message) || lastError?.status === 401 || lastError?.status === 403) {
    return "Gemini API Key 无效或没有权限。请检查网站后台配置的 GEMINI_API_KEY。";
  }
  if (/quota|rate limit/i.test(message) || lastError?.status === 429) {
    return "AI 分析请求太频繁或额度暂时受限。可以稍后再试，或者先手动填写并保存。";
  }
  if (/high demand|overloaded|temporar|try again later|unavailable|busy/i.test(message) || lastError?.status === 503) {
    return "AI 模型当前拥堵。我已经自动重试并切换备用模型，但这次仍未成功。请稍后再点一次分析，或先手动填写保存。";
  }
  return "AI 分析暂时失败。请稍后再试，或先手动填写保存。";
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function generateGeminiContent(apiKey, requestBody) {
  const errors = [];
  const models = modelCandidates();

  for (const model of models) {
    const attempts = model === models[0] ? 2 : 1;
    for (let attempt = 0; attempt < attempts; attempt += 1) {
      let response;
      try {
        response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${apiKey}`, {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify(requestBody),
          signal: AbortSignal.timeout(24000),
        });
      } catch (error) {
        const message = error instanceof Error ? error.message : String(error);
        errors.push({ model, status: 0, message });
        if (attempt + 1 < attempts) await delay(450);
        continue;
      }

      const payload = await readGeminiPayload(response);
      if (response.ok) return { model, payload };

      const message = errorMessage(payload);
      errors.push({ model, status: response.status, message });

      if (!isRetryable(response.status, message) && response.status !== 404) {
        const error = new Error(friendlyGeminiError(errors[errors.length - 1], errors));
        error.status = response.status;
        error.details = errors;
        throw error;
      }

      if (attempt + 1 < attempts) await delay(450);
    }
  }

  const lastError = errors[errors.length - 1] || { status: 503, message: "Gemini request failed." };
  const error = new Error(friendlyGeminiError(lastError, errors));
  error.status = lastError.status || 503;
  error.details = errors;
  throw error;
}
