import { createClient } from "@supabase/supabase-js";

export class SessionAuthError extends Error {
  constructor(status, message, extra) {
    super(message);
    this.status = status;
    if (extra) Object.assign(this, extra);
  }
}

const ERROR_CODES = { 400: "bad_request", 401: "unauthorized", 403: "forbidden", 405: "method_not_allowed", 429: "rate_limited" };

export function errorCodeFor(status) {
  return ERROR_CODES[status] || "error";
}

// Unlike the ingest endpoints, analyze-meal/analyze-body never touch the
// database — the only two error sources here are (a) SessionAuthError,
// which we throw ourselves with a deliberately safe message, and (b)
// errors surfaced by gemini.js's generateGeminiContent(), which always
// passes through friendlyGeminiError() and therefore also carries a safe,
// human-written message plus a numeric `.status` (even for 5xx cases like
// "model overloaded"). So any error with a numeric `.status` is trusted;
// only a genuinely unexpected/unclassified exception (no `.status` at all)
// gets collapsed into a generic message, with the real detail logged
// server-side only.
export function respondError(res, error, logLabel) {
  const hasKnownStatus = error instanceof SessionAuthError || Number.isInteger(error?.status);
  const status = hasKnownStatus ? error.status : 500;
  if (error instanceof SessionAuthError && error.retryAfterSeconds) {
    res.setHeader("retry-after", String(error.retryAfterSeconds));
  }
  const send = (payload) => {
    res.statusCode = status;
    res.setHeader("content-type", "application/json; charset=utf-8");
    res.end(JSON.stringify(payload));
  };
  if (!hasKnownStatus) {
    console.error(`[${logLabel}] internal error:`, error?.message || error);
    return send({ error: "Internal server error.", code: "internal_error" });
  }
  return send({ error: error?.message || "Request failed.", code: errorCodeFor(status) });
}

export function extractBearerToken(req) {
  const header = String(req.headers.authorization || "");
  const token = header.match(/^Bearer\s+(.+)$/i)?.[1]?.trim();
  if (!token) throw new SessionAuthError(401, "Missing bearer token.");
  return token;
}

// Asks the Supabase Auth server itself whether `token` is a currently valid
// session (rather than decoding the JWT locally) — this also confirms the
// token hasn't expired or been revoked. `supabase` is an injected client so
// this function is unit-testable without a network call; production always
// goes through requireSupabaseUser(), which supplies the real anon client.
export async function verifySupabaseToken(supabase, token) {
  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user) throw new SessionAuthError(401, "Invalid or expired session.");
  return data.user;
}

let cachedAnonClient = null;

function getAnonSupabaseClient() {
  if (cachedAnonClient) return cachedAnonClient;
  const supabaseUrl = process.env.SUPABASE_URL || process.env.VITE_SUPABASE_URL;
  const anonKey = process.env.SUPABASE_ANON_KEY || process.env.VITE_SUPABASE_ANON_KEY;
  if (!supabaseUrl || !anonKey) throw new SessionAuthError(500, "Supabase is not configured on the server.");
  cachedAnonClient = createClient(supabaseUrl, anonKey, { auth: { persistSession: false } });
  return cachedAnonClient;
}

// `supabaseClientOverride` only exists so tests can inject a stub client
// instead of hitting a live Supabase project — production callers (the
// handler files) never pass it, and the real anon client is used.
export async function requireSupabaseUser(req, supabaseClientOverride) {
  const token = extractBearerToken(req);
  const supabase = supabaseClientOverride || getAnonSupabaseClient();
  return verifySupabaseToken(supabase, token);
}

// Best-effort, single-process in-memory rate limit — NOT a distributed
// limiter. Vercel can run multiple concurrent instances of this function
// across regions and cold starts with no shared memory between them, so a
// caller that spreads requests across instances (or hits a fresh cold
// start) can exceed this ceiling. This only raises the bar for a single
// browser tab or script hammering one warm instance; it does not stop
// deliberate distributed abuse. A real fix would need a shared store
// (e.g. a Postgres/Redis-backed limiter), which is out of scope here.
const RATE_LIMIT_WINDOW_MS = 10 * 60 * 1000;
const RATE_LIMIT_MAX_REQUESTS = 12;
const requestLog = new Map();

export function checkRateLimit(userId, now = Date.now()) {
  const timestamps = (requestLog.get(userId) || []).filter((t) => now - t < RATE_LIMIT_WINDOW_MS);
  if (timestamps.length >= RATE_LIMIT_MAX_REQUESTS) {
    requestLog.set(userId, timestamps);
    const retryAfterMs = RATE_LIMIT_WINDOW_MS - (now - timestamps[0]);
    throw new SessionAuthError(429, "AI 分析请求过于频繁，请稍后再试。", {
      retryAfterSeconds: Math.max(1, Math.ceil(retryAfterMs / 1000)),
    });
  }
  timestamps.push(now);
  requestLog.set(userId, timestamps);
}

export function __resetRateLimitStoreForTests() {
  requestLog.clear();
}
