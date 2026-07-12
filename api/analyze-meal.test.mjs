import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import handler from "./analyze-meal.js";
import { __resetRateLimitStoreForTests } from "./_lib/sessionAuth.js";

// Failure-path scenarios assert the Gemini stub was called 0 times, proving
// auth/rate-limit/validation actually gate the Gemini call rather than just
// happening to return an error status for unrelated reasons. Success-path
// scenarios inject a stub generateGeminiContent (never the real network
// function from ./gemini.js) and assert it was called exactly once with the
// expected shape, and that the handler returns 200 with the expected body.
// GEMINI_API_KEY is a placeholder purely to get past the handler's "is
// Gemini configured" check — it is never sent anywhere in these tests.

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
  return { method, headers, url: "/api/analyze-meal", body };
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

// Records every call so tests can assert both "called once" and "called
// with the expected content" without ever touching the real Gemini API.
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

test("unsupported method (GET) -> 405", async () => {
  const { status } = await run(makeReq({ method: "GET" }));
  assert.equal(status, 405);
});

test("missing Authorization header -> 401, Gemini stub called 0 times", async () => {
  const generateGeminiContent = mockGemini({});
  const { status, body } = await run(
    makeReq({ body: { hint: "一碗牛肉面" } }),
    { generateGeminiContent },
  );
  assert.equal(status, 401);
  assert.equal(body.code, "unauthorized");
  assert.equal(generateGeminiContent.calls.length, 0);
});

test("invalid/expired token -> 401, Gemini stub called 0 times", async () => {
  const supabase = { auth: { getUser: async () => ({ data: { user: null }, error: { message: "expired" } }) } };
  const generateGeminiContent = mockGemini({});
  const { status } = await run(
    makeReq({ headers: { authorization: "Bearer bad-token" }, body: { hint: "一碗牛肉面" } }),
    { supabase, generateGeminiContent },
  );
  assert.equal(status, 401);
  assert.equal(generateGeminiContent.calls.length, 0);
});

test("valid session, empty body (no photos, no hint) -> 400, Gemini stub called 0 times", async () => {
  const generateGeminiContent = mockGemini({});
  const { status, body } = await run(
    makeReq({ headers: { authorization: "Bearer good-token" }, body: {} }),
    { supabase: mockValidAuth("user-empty-body"), generateGeminiContent },
  );
  assert.equal(status, 400);
  assert.equal(body.code, "bad_request");
  assert.equal(generateGeminiContent.calls.length, 0);
});

test("text-only mode (no photos, just a hint) without Authorization -> 401", async () => {
  const { status } = await run(makeReq({ headers: {}, body: { hint: "一碗牛肉面" } }));
  assert.equal(status, 401);
});

test("SUCCESS: valid session + text-only hint -> 200, Gemini stub called once with the hint in the prompt", async () => {
  const analysis = {
    dishName: "牛肉面",
    confidence: 0.55,
    total: { grams: 450, calories: 620, protein: 28, carbs: 70, fat: 18, fiber: 3 },
    items: [{ name: "牛肉面", grams: 450, calories: 620, protein: 28, carbs: 70, fat: 18, fiber: 3, reasoning: "常见家常份量估算" }],
    notes: "纯文字估算，建议核对份量。",
  };
  const generateGeminiContent = mockGemini(analysis);
  const { status, body } = await run(
    makeReq({ headers: { authorization: "Bearer good-token" }, body: { hint: "一碗牛肉面" } }),
    { supabase: mockValidAuth("user-text-success"), generateGeminiContent },
  );

  assert.equal(status, 200);
  assert.equal(generateGeminiContent.calls.length, 1);

  const [call] = generateGeminiContent.calls;
  assert.equal(call.apiKey, "test-key-not-real");
  const promptText = call.requestBody.contents[0].parts[0].text;
  assert.ok(promptText.includes("一碗牛肉面"), "prompt sent to Gemini must include the user's hint");
  assert.ok(promptText.includes("没有上传照片"), "text-only prompt branch must be used when there are no photos");
  assert.equal(call.requestBody.contents[0].parts.length, 1, "no image parts should be sent in text-only mode");

  assert.equal(body.ok, true);
  assert.equal(body.model, "stub-model");
  assert.equal(body.analysis.dishName, "牛肉面");
  assert.equal(body.analysis.total.calories, 620);
  assert.equal(body.analysis.items.length, 1);
});

test("SUCCESS: valid session + minimal photo -> 200, Gemini stub called once with an image part", async () => {
  const analysis = {
    dishName: "照片识别餐食",
    confidence: 0.7,
    total: { grams: 300, calories: 500, protein: 20, carbs: 60, fat: 15, fiber: 2 },
    items: [{ name: "米饭", grams: 200, calories: 260, protein: 4, carbs: 58, fat: 1, fiber: 1, reasoning: "碗装分量" }],
    notes: "照片估算结果。",
  };
  const generateGeminiContent = mockGemini(analysis);
  const { status, body } = await run(
    makeReq({
      headers: { authorization: "Bearer good-token" },
      body: { photos: [{ fileName: "meal.jpg", contentType: "image/jpeg", dataUrl: "data:image/jpeg;base64,QUFB" }] },
    }),
    { supabase: mockValidAuth("user-photo-success"), generateGeminiContent },
  );

  assert.equal(status, 200);
  assert.equal(generateGeminiContent.calls.length, 1);

  const [call] = generateGeminiContent.calls;
  const parts = call.requestBody.contents[0].parts;
  assert.equal(parts.length, 2, "photo mode must send the prompt text part plus one image part");
  assert.equal(parts[1].inlineData.mimeType, "image/jpeg");
  assert.equal(parts[1].inlineData.data, "QUFB");
  assert.ok(parts[0].text.includes("根据照片估算"), "photo prompt branch must be used when a photo is present");

  assert.equal(body.ok, true);
  assert.equal(body.analysis.dishName, "照片识别餐食");
});

test("deps cannot be smuggled through the request: calling handler(req, res) exactly as Vercel does ignores a body.deps override attempt", async () => {
  // Simulate exactly how Vercel invokes the handler in production: two
  // arguments only, no third `deps`. A request body that tries to sneak in
  // its own "deps"/"supabase"/"generateGeminiContent" must have zero effect
  // — the handler only ever reads its own third *function* argument, never
  // anything parsed out of req.body/req.headers/req.url.
  const maliciousBody = {
    hint: "一碗牛肉面",
    deps: { supabase: { auth: { getUser: async () => ({ data: { user: { id: "attacker" } }, error: null }) } } },
    supabase: { auth: { getUser: async () => ({ data: { user: { id: "attacker" } }, error: null }) } },
    generateGeminiContent: "not a function",
  };
  const req = makeReq({ headers: { authorization: "Bearer some-token" }, body: maliciousBody });
  const res = makeRes();
  // Note: no third argument passed to handler(), matching Vercel's real call.
  await handler(req, res);
  const body = res.body ? JSON.parse(res.body) : null;
  // Test env has no SUPABASE_URL/SUPABASE_ANON_KEY configured, so the real
  // (non-stubbed) auth path must be the one that ran, and it must fail with
  // a server-config error rather than succeeding via the smuggled fields.
  assert.equal(res.statusCode, 500);
  assert.ok(!JSON.stringify(body).includes("attacker"), "the smuggled mock user id must never appear in the response");
});

test("rate limit: 13th request from the same authenticated user in the window -> 429, Gemini stub stays at 12 calls", async () => {
  const supabase = mockValidAuth("user-rate-limited");
  const analysis = { dishName: "x", total: {}, items: [] };
  const generateGeminiContent = mockGemini(analysis);
  let lastStatus = 0;
  let lastBody = null;
  for (let i = 0; i < 13; i += 1) {
    const result = await run(
      makeReq({ headers: { authorization: "Bearer good-token" }, body: { hint: "米饭一碗" } }),
      { supabase, generateGeminiContent },
    );
    lastStatus = result.status;
    lastBody = result.body;
  }
  assert.equal(lastStatus, 429);
  assert.equal(lastBody.code, "rate_limited");
  // 12 successful calls reached Gemini; the 13th was blocked before that.
  assert.equal(generateGeminiContent.calls.length, 12);
});
