import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import {
  extractBearerToken,
  verifySupabaseToken,
  requireSupabaseUser,
  checkRateLimit,
  respondError,
  errorCodeFor,
  SessionAuthError,
  __resetRateLimitStoreForTests,
} from "./sessionAuth.js";

beforeEach(() => {
  __resetRateLimitStoreForTests();
});

function fakeReq(headers = {}) {
  return { headers };
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

function mockSupabase(getUserImpl) {
  return { auth: { getUser: getUserImpl } };
}

test("extractBearerToken: missing Authorization header -> 401", () => {
  assert.throws(() => extractBearerToken(fakeReq()), (error) => {
    assert.ok(error instanceof SessionAuthError);
    assert.equal(error.status, 401);
    return true;
  });
});

test("extractBearerToken: non-Bearer scheme -> 401", () => {
  assert.throws(() => extractBearerToken(fakeReq({ authorization: "Basic xyz" })), (error) => {
    assert.equal(error.status, 401);
    return true;
  });
});

test("extractBearerToken: well-formed Bearer header -> returns the token", () => {
  const token = extractBearerToken(fakeReq({ authorization: "Bearer abc.def.ghi" }));
  assert.equal(token, "abc.def.ghi");
});

test("verifySupabaseToken: Supabase Auth server rejects the token -> 401 (no raw error leaked)", async () => {
  const supabase = mockSupabase(async () => ({ data: { user: null }, error: { message: "invalid JWT: raw supabase internals" } }));
  await assert.rejects(
    () => verifySupabaseToken(supabase, "expired-or-invalid-token"),
    (error) => {
      assert.ok(error instanceof SessionAuthError);
      assert.equal(error.status, 401);
      assert.equal(error.message, "Invalid or expired session.");
      assert.ok(!error.message.includes("raw supabase internals"));
      return true;
    },
  );
});

test("verifySupabaseToken: Supabase Auth server confirms the token -> returns the user", async () => {
  const supabase = mockSupabase(async (token) => {
    assert.equal(token, "a-valid-token");
    return { data: { user: { id: "user-123", email: "person@example.com" } }, error: null };
  });
  const user = await verifySupabaseToken(supabase, "a-valid-token");
  assert.equal(user.id, "user-123");
});

test("requireSupabaseUser: injected client is used end-to-end (no network) when token is valid", async () => {
  const supabase = mockSupabase(async () => ({ data: { user: { id: "user-abc" } }, error: null }));
  const user = await requireSupabaseUser(fakeReq({ authorization: "Bearer whatever" }), supabase);
  assert.equal(user.id, "user-abc");
});

test("requireSupabaseUser: missing header short-circuits before ever touching the injected client", async () => {
  const supabase = mockSupabase(() => {
    throw new Error("should not be called");
  });
  await assert.rejects(() => requireSupabaseUser(fakeReq(), supabase), (error) => {
    assert.equal(error.status, 401);
    return true;
  });
});

test("checkRateLimit: allows up to the configured ceiling, then rejects with 429 + retryAfterSeconds", () => {
  const userId = "rate-limit-user-1";
  const now = Date.now();
  for (let i = 0; i < 12; i += 1) {
    checkRateLimit(userId, now + i);
  }
  assert.throws(() => checkRateLimit(userId, now + 12), (error) => {
    assert.ok(error instanceof SessionAuthError);
    assert.equal(error.status, 429);
    assert.ok(Number.isInteger(error.retryAfterSeconds) && error.retryAfterSeconds > 0);
    return true;
  });
});

test("checkRateLimit: window expiry lets requests through again", () => {
  const userId = "rate-limit-user-2";
  const now = Date.now();
  for (let i = 0; i < 12; i += 1) checkRateLimit(userId, now + i);
  assert.throws(() => checkRateLimit(userId, now + 1));
  // 10 minutes + 1ms later, the earliest timestamp has aged out of the window.
  assert.doesNotThrow(() => checkRateLimit(userId, now + 10 * 60 * 1000 + 1));
});

test("checkRateLimit: separate users have independent counters", () => {
  const now = Date.now();
  for (let i = 0; i < 12; i += 1) checkRateLimit("user-a", now + i);
  assert.doesNotThrow(() => checkRateLimit("user-b", now));
});

test("respondError: SessionAuthError message and status pass through unchanged", () => {
  const res = makeRes();
  respondError(res, new SessionAuthError(400, "请上传照片，或者至少填写一句文字说明。"), "test");
  assert.equal(res.statusCode, 400);
  const body = JSON.parse(res.body);
  assert.equal(body.error, "请上传照片，或者至少填写一句文字说明。");
  assert.equal(body.code, errorCodeFor(400));
});

test("respondError: a Gemini-originated error (has .status, safe message) passes through, including 5xx", () => {
  const res = makeRes();
  const geminiError = new Error("AI 模型当前拥堵。我已经自动重试并切换备用模型，但这次仍未成功。");
  geminiError.status = 503;
  respondError(res, geminiError, "test");
  assert.equal(res.statusCode, 503);
  const body = JSON.parse(res.body);
  assert.equal(body.error, geminiError.message);
});

test("respondError: a truly unclassified exception (no .status) is collapsed to a generic 500", () => {
  const res = makeRes();
  respondError(res, new TypeError("Cannot read properties of undefined (reading 'foo')"), "test");
  assert.equal(res.statusCode, 500);
  const body = JSON.parse(res.body);
  assert.equal(body.error, "Internal server error.");
  assert.ok(!body.error.includes("undefined"));
});

test("respondError: rate-limit error sets Retry-After header", () => {
  const res = makeRes();
  respondError(res, new SessionAuthError(429, "太频繁了。", { retryAfterSeconds: 42 }), "test");
  assert.equal(res.statusCode, 429);
  assert.equal(res.headers["retry-after"], "42");
});
