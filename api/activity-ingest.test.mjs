import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import handler from "./activity-ingest.js";

// Same constraint as api/ingest.test.mjs: every scenario here must resolve
// (success or failure) before any real Supabase network call. GET requests
// that reach listRecentDailyActivities() DO hit the network, so this file
// deliberately avoids exercising that branch — see the "not automated" note
// in docs/AUDIT.md for what that means for coverage.

const ENV_KEYS = ["DIARY_INGEST_TOKEN", "DIARY_USER_ID", "DIARY_USER_EMAIL", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"];
let savedEnv;

beforeEach(() => {
  savedEnv = Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
  process.env.DIARY_INGEST_TOKEN = "test-token";
  process.env.DIARY_USER_ID = "owner-uuid";
  process.env.SUPABASE_URL = "https://example.invalid";
  process.env.SUPABASE_SERVICE_ROLE_KEY = "test-service-role-key-not-real";
});

afterEach(() => {
  for (const key of ENV_KEYS) {
    if (savedEnv[key] === undefined) delete process.env[key];
    else process.env[key] = savedEnv[key];
  }
});

function makeReq({ method = "POST", headers = {}, body = {}, url = "/api/activity-ingest" } = {}) {
  return { method, headers, url, body };
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

async function run(req) {
  const res = makeRes();
  await handler(req, res);
  return { status: res.statusCode, body: res.body ? JSON.parse(res.body) : null };
}

test("unsupported method (DELETE) -> 405", async () => {
  const { status } = await run(makeReq({ method: "DELETE", headers: { authorization: "Bearer test-token" } }));
  assert.equal(status, 405);
});

test("missing Authorization header -> 401", async () => {
  const { status } = await run(makeReq({ headers: {} }));
  assert.equal(status, 401);
});

test("invalid bearer token -> 401", async () => {
  const { status } = await run(makeReq({ headers: { authorization: "Bearer not-the-real-token" } }));
  assert.equal(status, 401);
});

test("correct token as a URL query param (the old Shortcuts \"simple URL\" method), no header -> 400 query_token_not_supported, rejected before any network call", async () => {
  // GET is intentionally used here: the query-token check runs before the
  // method branches into readJson/payloadFromQuery, so this is safe and
  // never reaches listRecentDailyActivities()/Supabase.
  const { status, body } = await run(makeReq({
    method: "GET",
    headers: {},
    url: "/api/activity-ingest?token=test-token&write=1&date=2026-07-01&steps=8000",
  }));
  assert.equal(status, 400);
  assert.equal(body.code, "query_token_not_supported");
  assert.ok(!JSON.stringify(body).includes("test-token"), "the token value must never appear in the response body");
});

test("correct Authorization header PLUS a query token param -> still rejected, forcing the caller to clean up the URL", async () => {
  const { status, body } = await run(makeReq({
    headers: { authorization: "Bearer test-token" },
    url: "/api/activity-ingest?token=test-token",
  }));
  assert.equal(status, 400);
  assert.equal(body.code, "query_token_not_supported");
});

test("valid token but payload.userId claims a different account -> 403, write is blocked before touching Supabase", async () => {
  const { status, body } = await run(makeReq({
    headers: { authorization: "Bearer test-token" },
    body: { userId: "some-other-users-uuid", date: "2026-01-01", steps: 8000 },
  }));
  assert.equal(status, 403);
  assert.equal(body.code, "forbidden");
});

test("valid token, all-zero activity data -> 400 (existing business rule, unaffected by this fix)", async () => {
  const { status } = await run(makeReq({
    headers: { authorization: "Bearer test-token" },
    body: { date: "2026-01-01" },
  }));
  assert.equal(status, 400);
});
