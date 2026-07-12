import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import handler from "./analyze-body.js";
import { __resetRateLimitStoreForTests } from "./_lib/sessionAuth.js";

// Same approach as api/analyze-meal.test.mjs: failure paths assert the
// Gemini stub was called 0 times, and the success path injects a stub
// generateGeminiContent (never the real network function) and asserts it
// was called exactly once, with the handler returning 200 and the expected
// body shape.

let savedApiKey;

beforeEach(() => {
  __resetRateLimitStoreForTests();
  savedApiKey = process.env.GEMINI_API_KEY;
  process.env.GEMINI_API_KEY = "test-key-not-real";
});

afterEach(() => {
  if (savedApiKey === undefined) delete process.env.GEMINI_API_KEY;
  else process.env.GEMINI_API_KEY = savedApiKey;
});

function makeReq({ method = "POST", headers = {}, body = {} } = {}) {
  return { method, headers, url: "/api/analyze-body", body };
}

function makeRes() {
  return {
    statusCode: 200,
    headers: {},
    body: null,
    setHeader(name, value) {
      this.headers[name] = value;
    },
    end(text) {
      this.body = text;
    },
  };
}

async function run(req, deps) {
  const res = makeRes();
  await handler(req, res, deps);
  return { status: res.statusCode, body: res.body ? JSON.parse(res.body) : null };
}

function mockValidAuth(userId = "user-1") {
  return { auth: { getUser: async () => ({ data: { user: { id: userId } }, error: null }) } };
}

function mockGemini(analysisPayload, { model = "stub-model" } = {}) {
  const calls = [];
  const fn = async (apiKey, requestBody) => {
    calls.push({ apiKey, requestBody });
    return {
      model,
      payload: {
        candidates: [{ content: { parts: [{ text: JSON.stringify(analysisPayload) }] } }],
      },
    };
  };
  fn.calls = calls;
  return fn;
}

const MIN_SCREENSHOT = { fileName: "scale.jpg", contentType: "image/jpeg", dataUrl: "data:image/jpeg;base64,QUFB" };

test("unsupported method (PUT) -> 405", async () => {
  const { status } = await run(makeReq({ method: "PUT" }));
  assert.equal(status, 405);
});

test("missing Authorization header -> 401, Gemini stub called 0 times", async () => {
  const generateGeminiContent = mockGemini({});
  const { status } = await run(
    makeReq({ body: { screenshot: MIN_SCREENSHOT } }),
    { generateGeminiContent },
  );
  assert.equal(status, 401);
  assert.equal(generateGeminiContent.calls.length, 0);
});

test("invalid/expired token -> 401, Gemini stub called 0 times", async () => {
  const supabase = { auth: { getUser: async () => ({ data: { user: null }, error: { message: "expired" } }) } };
  const generateGeminiContent = mockGemini({});
  const { status } = await run(
    makeReq({ headers: { authorization: "Bearer bad-token" }, body: { screenshot: MIN_SCREENSHOT } }),
    { supabase, generateGeminiContent },
  );
  assert.equal(status, 401);
  assert.equal(generateGeminiContent.calls.length, 0);
});

test("valid session, missing screenshot -> 400, Gemini stub called 0 times", async () => {
  const generateGeminiContent = mockGemini({});
  const { status, body } = await run(
    makeReq({ headers: { authorization: "Bearer good-token" }, body: {} }),
    { supabase: mockValidAuth("user-empty-body"), generateGeminiContent },
  );
  assert.equal(status, 400);
  assert.equal(body.code, "bad_request");
  assert.equal(generateGeminiContent.calls.length, 0);
});

test("SUCCESS: valid session + minimal screenshot -> 200, Gemini stub called once with the image", async () => {
  const analysis = {
    confidence: 0.82,
    date: "2026-07-01",
    measuredAt: "2026-07-01T08:00",
    weightKg: 70.5,
    bmi: 22.1,
    bodyFatPercent: 18.4,
    notes: "体脂秤截图 OCR 识别结果。",
  };
  const generateGeminiContent = mockGemini(analysis);
  const { status, body } = await run(
    makeReq({ headers: { authorization: "Bearer good-token" }, body: { screenshot: MIN_SCREENSHOT } }),
    { supabase: mockValidAuth("user-screenshot-success"), generateGeminiContent },
  );

  assert.equal(status, 200);
  assert.equal(generateGeminiContent.calls.length, 1);

  const [call] = generateGeminiContent.calls;
  assert.equal(call.apiKey, "test-key-not-real");
  const parts = call.requestBody.contents[0].parts;
  assert.equal(parts.length, 2, "must send the prompt text part plus the screenshot image part");
  assert.equal(parts[1].inlineData.mimeType, "image/jpeg");
  assert.equal(parts[1].inlineData.data, "QUFB");
  assert.ok(parts[0].text.includes("体脂秤截图"), "prompt must be the body-screenshot OCR prompt");

  assert.equal(body.ok, true);
  assert.equal(body.model, "stub-model");
  assert.equal(body.analysis.weightKg, 70.5);
  assert.equal(body.analysis.bmi, 22.1);
});

test("rate limit: 13th request from the same authenticated user in the window -> 429, Gemini stub stays at 12 calls", async () => {
  const supabase = mockValidAuth("user-rate-limited");
  const generateGeminiContent = mockGemini({ confidence: 0.5 });
  let lastStatus = 0;
  let lastBody = null;
  for (let i = 0; i < 13; i += 1) {
    const result = await run(
      makeReq({ headers: { authorization: "Bearer good-token" }, body: { screenshot: MIN_SCREENSHOT } }),
      { supabase, generateGeminiContent },
    );
    lastStatus = result.status;
    lastBody = result.body;
  }
  assert.equal(lastStatus, 429);
  assert.equal(lastBody.code, "rate_limited");
  assert.equal(generateGeminiContent.calls.length, 12);
});
