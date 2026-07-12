import { createClient } from "@supabase/supabase-js";
import { timingSafeEqual } from "node:crypto";

export class IngestAuthError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const ERROR_CODES = { 400: "bad_request", 401: "unauthorized", 403: "forbidden", 405: "method_not_allowed" };

export function errorCodeFor(status) {
  return ERROR_CODES[status] || "error";
}

// Every 4xx here is a message we wrote ourselves (auth/validation), safe to
// return as-is. Anything else (network/DB errors, unexpected exceptions) is
// logged server-side only and replaced with a generic message, so raw
// Postgres/Supabase error text never reaches the caller.
export function respondError(res, error, logLabel) {
  const status = error instanceof IngestAuthError || Number.isInteger(error?.status) ? error.status : 500;
  const json = (payload) => {
    res.statusCode = status >= 500 ? 500 : status;
    res.setHeader("content-type", "application/json; charset=utf-8");
    res.end(JSON.stringify(payload));
  };
  if (status >= 500) {
    console.error(`[${logLabel}] internal error:`, error?.message || error);
    return json({ error: "Internal server error.", code: "internal_error" });
  }
  return json({ error: error?.message || "Request failed.", code: errorCodeFor(status) });
}

function cleanToken(value) {
  return String(Array.isArray(value) ? value[0] : value)
    .trim()
    .replace(/^DIARY_INGEST_TOKEN\s*=\s*/i, "")
    .replace(/^Bearer\s+/i, "")
    .replace(/^["']|["']$/g, "")
    .trim();
}

// Constant-time string comparison so a mismatched token can't be recovered
// byte-by-byte from response timing (plain !== short-circuits at the first
// differing character). Buffers of different lengths still leak *length*
// (timingSafeEqual requires equal-length inputs, so we compare against a
// zero buffer instead and always return false) — an accepted, minor
// trade-off; the token's *content* never affects timing either way. Never
// throws: mismatched-length inputs are handled explicitly instead of
// letting timingSafeEqual raise a RangeError.
function safeCompare(a, b) {
  const bufA = Buffer.from(String(a));
  const bufB = Buffer.from(String(b));
  if (bufA.length !== bufB.length) {
    timingSafeEqual(bufA, Buffer.alloc(bufA.length));
    return false;
  }
  return timingSafeEqual(bufA, bufB);
}

// Legacy query-string aliases the token used to be accepted under. Any of
// these being present in the URL — even alongside a correct Authorization
// header — is treated as a hard error, not silently ignored, so callers are
// forced to stop putting the secret in a URL rather than quietly degrading.
const QUERY_TOKEN_PARAMS = ["token", "diaryToken", "apiKey", "key"];

// These two ingest endpoints have no browser session behind them — the only
// callers are the iPhone Shortcuts automation and a local CLI script, neither
// of which can hold a Supabase user session. DIARY_INGEST_TOKEN is therefore
// the sole authentication factor by design, not a stand-in for user login.
//
// The token is accepted ONLY via `Authorization: Bearer <token>`. It is
// never read from the URL query string, the request body, cookies, or any
// other header — URLs and request bodies routinely end up in proxy/edge
// access logs, browser history, and Shortcuts run logs, so a token that can
// travel there is effectively no longer secret.
export function requireIngestToken(req) {
  const token = process.env.DIARY_INGEST_TOKEN;
  if (!token) return { ok: false, status: 500, message: "DIARY_INGEST_TOKEN is not configured." };

  const url = new URL(req.url || "/", "https://placeholder.invalid");
  if (QUERY_TOKEN_PARAMS.some((param) => url.searchParams.has(param))) {
    return {
      ok: false,
      status: 400,
      code: "query_token_not_supported",
      message: "Sending the token as a URL query parameter is no longer supported. Send it as an \"Authorization: Bearer <token>\" header instead.",
    };
  }

  const header = String(req.headers.authorization || "");
  const bearer = header.match(/^Bearer\s+(.+)$/i)?.[1] || "";
  if (!bearer) return { ok: false, status: 401, message: "Missing bearer token." };

  const provided = cleanToken(bearer);
  if (!provided || !safeCompare(provided, token)) return { ok: false, status: 401, message: "Invalid bearer token." };
  return { ok: true };
}

export function createServiceRoleClient() {
  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!supabaseUrl || !serviceRoleKey) {
    throw new IngestAuthError(500, "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.");
  }
  return createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
}

async function findUserByEmail(supabase, email) {
  let page = 1;
  while (page < 20) {
    const { data, error } = await supabase.auth.admin.listUsers({ page, perPage: 1000 });
    if (error) throw error;
    const user = data.users.find((item) => item.email?.toLowerCase() === email.toLowerCase());
    if (user) return user;
    if (!data.users.length) break;
    page += 1;
  }
  return null;
}

// The account these endpoints are allowed to write to comes ONLY from server
// configuration (DIARY_USER_ID / DIARY_USER_EMAIL) — never from the request
// body. A caller holding the shared token can only ever act on this single,
// pre-configured account, matching the app's single-user design intent.
//
// If the request body still carries a legacy userId/userEmail field, it is
// treated as a client-declared expectation, not a source of identity: it is
// checked against the resolved account and rejected (403) on mismatch rather
// than silently switching accounts.
export async function resolveTrustedUserId(supabase, payload) {
  const configuredId = process.env.DIARY_USER_ID;
  const configuredEmail = process.env.DIARY_USER_EMAIL;

  let trustedId;
  let trustedEmail = null;

  if (configuredId) {
    trustedId = configuredId;
  } else if (configuredEmail) {
    const user = await findUserByEmail(supabase, configuredEmail);
    if (!user) throw new IngestAuthError(500, "No Supabase user found for the configured DIARY_USER_EMAIL.");
    trustedId = user.id;
    trustedEmail = user.email || null;
  } else {
    throw new IngestAuthError(500, "Server is missing DIARY_USER_ID or DIARY_USER_EMAIL configuration.");
  }

  const claimedId = typeof payload?.userId === "string" ? payload.userId.trim() : "";
  const claimedEmail = typeof payload?.userEmail === "string" ? payload.userEmail.trim().toLowerCase() : "";

  if (claimedId && claimedId !== trustedId) {
    console.warn("[ingest-auth] rejected request: payload.userId did not match the configured account.");
    throw new IngestAuthError(403, "Request identity does not match the configured account.");
  }
  if (claimedEmail && trustedEmail && claimedEmail !== trustedEmail.toLowerCase()) {
    console.warn("[ingest-auth] rejected request: payload.userEmail did not match the configured account.");
    throw new IngestAuthError(403, "Request identity does not match the configured account.");
  }

  return trustedId;
}
