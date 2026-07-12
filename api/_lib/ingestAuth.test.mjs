import { test, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { requireIngestToken, resolveTrustedUserId, IngestAuthError, respondError, errorCodeFor } from "./ingestAuth.js";

const ENV_KEYS = ["DIARY_INGEST_TOKEN", "DIARY_USER_ID", "DIARY_USER_EMAIL"];
let savedEnv;

beforeEach(() => {
  savedEnv = Object.fromEntries(ENV_KEYS.map((key) => [key, process.env[key]]));
  for (const key of ENV_KEYS) delete process.env[key];
});

afterEach(() => {
  for (const key of ENV_KEYS) {
    if (savedEnv[key] === undefined) delete process.env[key];
    else process.env[key] = savedEnv[key];
  }
});

function fakeReq({ headers = {}, url = "/api/ingest", body } = {}) {
  return { headers, url, body };
}

// A Supabase client stub that fails the test if any of its methods are
// actually invoked — the DIARY_USER_ID fast path must never touch it.
function unusedSupabaseClient() {
  return {
    auth: {
      admin: {
        listUsers: () => {
          throw new Error("listUsers should not be called when DIARY_USER_ID is configured.");
        },
      },
    },
  };
}

test("requireIngestToken: missing Authorization header -> 401", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  const result = requireIngestToken(fakeReq());
  assert.equal(result.ok, false);
  assert.equal(result.status, 401);
});

test("requireIngestToken: non-Bearer Authorization header -> 401", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  const result = requireIngestToken(fakeReq({ headers: { authorization: "Basic abc123" } }));
  assert.equal(result.ok, false);
  assert.equal(result.status, 401);
});

test("requireIngestToken: wrong Bearer token -> 401", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  const result = requireIngestToken(fakeReq({ headers: { authorization: "Bearer wrong-value" } }));
  assert.equal(result.ok, false);
  assert.equal(result.status, 401);
});

test("requireIngestToken: correct Bearer token -> ok", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  const result = requireIngestToken(fakeReq({ headers: { authorization: "Bearer secret-token" } }));
  assert.equal(result.ok, true);
});

test("requireIngestToken: Bearer token of a different length than the configured one -> 401, does not throw (constant-time compare must handle length mismatch safely)", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  assert.doesNotThrow(() => {
    const result = requireIngestToken(fakeReq({ headers: { authorization: "Bearer short" } }));
    assert.equal(result.ok, false);
    assert.equal(result.status, 401);
  });
});

test("requireIngestToken: a much longer wrong Bearer token -> 401, does not throw", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  assert.doesNotThrow(() => {
    const result = requireIngestToken(fakeReq({ headers: { authorization: `Bearer ${"x".repeat(200)}` } }));
    assert.equal(result.ok, false);
    assert.equal(result.status, 401);
  });
});

test("requireIngestToken: server missing DIARY_INGEST_TOKEN config -> 500", () => {
  const result = requireIngestToken(fakeReq({ headers: { authorization: "Bearer anything" } }));
  assert.equal(result.ok, false);
  assert.equal(result.status, 500);
});

test("requireIngestToken: token in x-diary-token header is no longer accepted (custom header removed) -> 401 missing", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  const result = requireIngestToken(fakeReq({ headers: { "x-diary-token": "secret-token" } }));
  assert.equal(result.ok, false);
  assert.equal(result.status, 401);
});

test("requireIngestToken: token in request body is never used for auth, even with the correct value", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  const result = requireIngestToken(fakeReq({ body: { token: "secret-token", diaryToken: "secret-token" } }));
  assert.equal(result.ok, false);
  assert.equal(result.status, 401, "no Authorization header was sent, so this must still be Missing bearer token, not authenticated via body");
});

for (const param of ["token", "diaryToken", "apiKey", "key"]) {
  test(`requireIngestToken: correct token as ONLY the "${param}" query param (no header) -> 400 query_token_not_supported`, () => {
    process.env.DIARY_INGEST_TOKEN = "secret-token";
    const result = requireIngestToken(fakeReq({ url: `/api/activity-ingest?${param}=secret-token` }));
    assert.equal(result.ok, false);
    assert.equal(result.status, 400);
    assert.equal(result.code, "query_token_not_supported");
    assert.ok(!result.message.includes("secret-token"), "the error message must never echo the actual token value");
  });
}

test("requireIngestToken: CORRECT Authorization header PLUS a query token param -> still rejected (query token forces cleanup, doesn't just get ignored)", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  const result = requireIngestToken(fakeReq({
    headers: { authorization: "Bearer secret-token" },
    url: "/api/activity-ingest?token=secret-token&write=1",
  }));
  assert.equal(result.ok, false);
  assert.equal(result.status, 400);
  assert.equal(result.code, "query_token_not_supported");
});

test("requireIngestToken: WRONG query token param, even with a correct header -> still rejected as query_token_not_supported (presence alone is disqualifying)", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  const result = requireIngestToken(fakeReq({
    headers: { authorization: "Bearer secret-token" },
    url: "/api/activity-ingest?token=totally-wrong-value",
  }));
  assert.equal(result.ok, false);
  assert.equal(result.status, 400);
  assert.equal(result.code, "query_token_not_supported");
});

test("requireIngestToken: unrelated query params (date, steps, ...) do not trigger the query-token rejection", () => {
  process.env.DIARY_INGEST_TOKEN = "secret-token";
  const result = requireIngestToken(fakeReq({
    headers: { authorization: "Bearer secret-token" },
    url: "/api/activity-ingest?write=1&date=2026-07-01&steps=8000",
  }));
  assert.equal(result.ok, true);
});

test("resolveTrustedUserId: DIARY_USER_ID configured, no payload.userId -> returns configured id, never touches Supabase", async () => {
  process.env.DIARY_USER_ID = "owner-uuid";
  const id = await resolveTrustedUserId(unusedSupabaseClient(), {});
  assert.equal(id, "owner-uuid");
});

test("resolveTrustedUserId: payload.userId matches configured account -> allowed (no-op)", async () => {
  process.env.DIARY_USER_ID = "owner-uuid";
  const id = await resolveTrustedUserId(unusedSupabaseClient(), { userId: "owner-uuid" });
  assert.equal(id, "owner-uuid");
});

test("resolveTrustedUserId: payload.userId claims a DIFFERENT account -> rejected with 403 (the core IDOR fix)", async () => {
  process.env.DIARY_USER_ID = "owner-uuid";
  await assert.rejects(
    () => resolveTrustedUserId(unusedSupabaseClient(), { userId: "attacker-controlled-other-user-uuid" }),
    (error) => {
      assert.ok(error instanceof IngestAuthError);
      assert.equal(error.status, 403);
      return true;
    },
  );
});

test("resolveTrustedUserId: payload.userEmail claims a different account than the resolved email -> rejected with 403", async () => {
  process.env.DIARY_USER_EMAIL = "owner@example.com";
  const supabase = {
    auth: {
      admin: {
        listUsers: async () => ({ data: { users: [{ id: "owner-uuid", email: "owner@example.com" }] }, error: null }),
      },
    },
  };
  await assert.rejects(
    () => resolveTrustedUserId(supabase, { userEmail: "someone-else@example.com" }),
    (error) => {
      assert.ok(error instanceof IngestAuthError);
      assert.equal(error.status, 403);
      return true;
    },
  );
});

test("resolveTrustedUserId: neither DIARY_USER_ID nor DIARY_USER_EMAIL configured -> 500 (server misconfiguration, not a client error)", async () => {
  await assert.rejects(
    () => resolveTrustedUserId(unusedSupabaseClient(), { userId: "whatever" }),
    (error) => {
      assert.ok(error instanceof IngestAuthError);
      assert.equal(error.status, 500);
      return true;
    },
  );
});

test("respondError: IngestAuthError(400) is returned to the caller as-is", () => {
  const res = makeRes();
  respondError(res, new IngestAuthError(400, "items must be an array."), "test");
  assert.equal(res.statusCode, 400);
  const body = JSON.parse(res.body);
  assert.equal(body.error, "items must be an array.");
  assert.equal(body.code, errorCodeFor(400));
});

test("respondError: a raw/unexpected error never leaks its message to the client, only a generic 500", () => {
  const res = makeRes();
  respondError(res, new Error("relation \"food_items\" violates constraint xyz at db.internal.host"), "test");
  assert.equal(res.statusCode, 500);
  const body = JSON.parse(res.body);
  assert.equal(body.error, "Internal server error.");
  assert.ok(!body.error.includes("food_items"));
  assert.ok(!JSON.stringify(body).includes("db.internal.host"));
});

function makeRes() {
  return {
    statusCode: 200,
    body: null,
    setHeader() {},
    end(text) {
      this.body = text;
    },
  };
}
