import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import handler from "./ingest.js";

// These tests exercise the real exported handler, but every scenario below
// is designed to fail (or short-circuit) before any Supabase network call
// is made — see the comment on each test. No test here writes to, or even
// contacts, a live Supabase project.

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

function makeReq({ method = "POST", headers = {}, body = {}, url = "/api/ingest" } = {}) {
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

test("GET is not allowed on /api/ingest -> 405 (no network reached)", async () => {
  const { status } = await run(makeReq({ method: "GET", headers: { authorization: "Bearer test-token" } }));
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

test("correct token as a URL query param, no Authorization header -> 400 query_token_not_supported, not authenticated", async () => {
  const { status, body } = await run(makeReq({ headers: {}, url: "/api/ingest?token=test-token" }));
  assert.equal(status, 400);
  assert.equal(body.code, "query_token_not_supported");
  assert.ok(!JSON.stringify(body).includes("test-token"), "the token value must never appear in the response body");
});

test("correct Authorization header PLUS a query token param -> still rejected", async () => {
  const { status, body } = await run(makeReq({
    headers: { authorization: "Bearer test-token" },
    url: "/api/ingest?token=test-token",
  }));
  assert.equal(status, 400);
  assert.equal(body.code, "query_token_not_supported");
});

test("valid token but payload.userId claims a different account -> 403, write is blocked before touching Supabase", async () => {
  const { status, body } = await run(makeReq({
    headers: { authorization: "Bearer test-token" },
    body: { userId: "some-other-users-uuid", items: [{ sourceId: "x", date: "2026-01-01", meal: "breakfast", name: "test" }] },
  }));
  assert.equal(status, 403);
  assert.equal(body.code, "forbidden");
});

test("valid token, item missing required sourceId -> 400 (business validation, not a 500)", async () => {
  const { status, body } = await run(makeReq({
    headers: { authorization: "Bearer test-token" },
    body: { items: [{ date: "2026-01-01", meal: "breakfast", name: "test" }] },
  }));
  assert.equal(status, 400);
  assert.equal(body.code, "bad_request");
});

test("valid token, items is not an array -> 400", async () => {
  const { status } = await run(makeReq({
    headers: { authorization: "Bearer test-token" },
    body: { items: "not-an-array" },
  }));
  assert.equal(status, 400);
});
