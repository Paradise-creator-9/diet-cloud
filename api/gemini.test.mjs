import { test } from "node:test";
import assert from "node:assert/strict";
import * as geminiModule from "./gemini.js";

// api/gemini.js must never become an independently callable HTTP route.
// Vercel's Node.js builder only turns a file under /api into a Serverless
// Function when it has a default export shaped like (req, res) => {}; a
// module with only named exports is just bundled code, not a route. This
// test locks that in as a regression guard — if someone later adds
// `export default` to this file (e.g. while refactoring), it would bypass
// the auth/rate-limit checks in analyze-meal.js/analyze-body.js by exposing
// a raw, unauthenticated /api/gemini endpoint, and this test would fail.
test("api/gemini.js has no default export (must stay a non-routable shared module)", () => {
  assert.equal(geminiModule.default, undefined);
});

test("api/gemini.js exposes exactly the expected named export", () => {
  assert.deepEqual(Object.keys(geminiModule), ["generateGeminiContent"]);
  assert.equal(typeof geminiModule.generateGeminiContent, "function");
});
