import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

// These tests are purely static: they read the .sql files as text and
// pattern-match against them. They never connect to a database and never
// execute any SQL, so they cannot prove the SQL is syntactically valid or
// that it would actually apply cleanly against a real (or fresh) Supabase
// project — only that the *intended* private/owner-only shape is present
// in the files a human or CI would read. Actual application was verified
// separately, read-only, against the live production project via the
// Supabase MCP (see docs/AUDIT.md #1) — not by these tests.

const here = path.dirname(fileURLToPath(import.meta.url));

function read(relativePath) {
  return readFileSync(path.join(here, relativePath), "utf8");
}

const schemaSql = read("schema.sql");
const fixSql = read("fix-meal-photos-storage-permissions.sql");
const recoveredMigration = read("migrations/20260708041749_restrict_meal_photos_read_to_owner.sql");
const bucketPrivateMigration = read("migrations/20260712000000_set_meal_photos_bucket_private.sql");

const OWNER_FOLDER_CHECK = /\(storage\.foldername\(name\)\)\[1\]\s*=\s*\(select auth\.uid\(\)\)::text/;

function bucketInsertBlock(sql) {
  const match = sql.match(/insert into storage\.buckets[\s\S]*?on conflict[\s\S]*?;/);
  assert.ok(match, "expected an `insert into storage.buckets (...) ... on conflict ...;` statement");
  return match[0];
}

test("schema.sql: meal-photos bucket is inserted as private (public = false), not true", () => {
  const block = bucketInsertBlock(schemaSql);
  assert.match(block, /'meal-photos',\s*\n?\s*false,/, "bucket insert must declare public = false");
  assert.doesNotMatch(block, /'meal-photos',\s*\n?\s*true,/, "bucket insert must not declare public = true");
});

test("fix-meal-photos-storage-permissions.sql: meal-photos bucket is inserted as private (public = false), not true", () => {
  const block = bucketInsertBlock(fixSql);
  assert.match(block, /'meal-photos',\s*\n?\s*false,/);
  assert.doesNotMatch(block, /'meal-photos',\s*\n?\s*true,/);
});

test("schema.sql: no unrestricted public read policy remains for meal-photos", () => {
  // The old vulnerable shape was exactly this: a select policy whose USING
  // clause only checks bucket_id, with no per-folder ownership condition.
  assert.doesNotMatch(
    schemaSql,
    /create policy "meal_photos_public_read"/,
    "the old unrestricted read policy name must not be (re)created",
  );
  assert.doesNotMatch(
    schemaSql,
    /on storage\.objects for select\s*\nusing \(bucket_id = 'meal-photos'\);/,
    "must not have a SELECT policy gated only on bucket_id with no owner check",
  );
});

test("fix-meal-photos-storage-permissions.sql: no unrestricted public read policy remains", () => {
  assert.doesNotMatch(fixSql, /create policy "meal_photos_public_read"/);
  assert.doesNotMatch(fixSql, /on storage\.objects for select\s*\nusing \(bucket_id = 'meal-photos'\);/);
});

for (const [label, sql] of [
  ["schema.sql", schemaSql],
  ["fix-meal-photos-storage-permissions.sql", fixSql],
  ["migrations/20260708041749_restrict_meal_photos_read_to_owner.sql", recoveredMigration],
]) {
  test(`${label}: no "using (true)" or "with check (true)" appears anywhere`, () => {
    assert.doesNotMatch(sql, /using\s*\(\s*true\s*\)/i);
    assert.doesNotMatch(sql, /with check\s*\(\s*true\s*\)/i);
  });
}

test("schema.sql: meal-photos read/insert/update/delete policies are all owner-scoped via auth.uid() folder check", () => {
  const policyNames = ["meal_photos_read_own", "meal_photos_authenticated_insert_own", "meal_photos_authenticated_update_own", "meal_photos_authenticated_delete_own"];
  for (const name of policyNames) {
    const policyMatch = schemaSql.match(new RegExp(`create policy "${name}"[\\s\\S]*?;`));
    assert.ok(policyMatch, `expected to find policy "${name}" in schema.sql`);
    assert.match(policyMatch[0], OWNER_FOLDER_CHECK, `policy "${name}" must check (storage.foldername(name))[1] = auth.uid()`);
  }
});

test("fix-meal-photos-storage-permissions.sql: same four owner-scoped policies as schema.sql", () => {
  const policyNames = ["meal_photos_read_own", "meal_photos_authenticated_insert_own", "meal_photos_authenticated_update_own", "meal_photos_authenticated_delete_own"];
  for (const name of policyNames) {
    const policyMatch = fixSql.match(new RegExp(`create policy "${name}"[\\s\\S]*?;`));
    assert.ok(policyMatch, `expected to find policy "${name}" in fix-meal-photos-storage-permissions.sql`);
    assert.match(policyMatch[0], OWNER_FOLDER_CHECK);
  }
});

test("neither storage SQL file scopes any meal-photos policy by a client-supplied userId column/param instead of auth.uid()", () => {
  // Guards against a regression where someone "fixes" a policy by trusting
  // a request-supplied value instead of the server-verified auth.uid().
  for (const [label, sql] of [["schema.sql", schemaSql], ["fix-meal-photos-storage-permissions.sql", fixSql]]) {
    const meaPhotosPolicyBlocks = sql.match(/create policy "meal_photos_[\s\S]*?;/g) || [];
    assert.ok(meaPhotosPolicyBlocks.length >= 4, `${label}: expected at least 4 meal_photos policies`);
    for (const block of meaPhotosPolicyBlocks) {
      assert.doesNotMatch(block, /current_setting\(|request\.jwt|['"]?userId['"]?\s*=/i, `${label}: policy must not branch on a client-supplied identifier — ${block.slice(0, 60)}...`);
    }
  }
});

test("recovered migration 20260708041749: matches the exact statements read from production's schema_migrations table", () => {
  // This is a regression guard for the migration FILE itself (does it still
  // say what we recovered), not a check against a live database.
  assert.match(recoveredMigration, /drop policy if exists "meal_photos_public_read" on storage\.objects;/);
  assert.match(recoveredMigration, /create policy "meal_photos_read_own"/);
  assert.match(recoveredMigration, /to authenticated/);
  assert.match(recoveredMigration, OWNER_FOLDER_CHECK);
  // This migration intentionally does NOT touch the storage.buckets table
  // (only policies) — confirmed against production; see the file's own
  // comment for why. Check only the executable statements, not the prose
  // comments, which legitimately mention storage.buckets while explaining
  // that fact.
  const withoutComments = recoveredMigration.replace(/--.*$/gm, "");
  assert.doesNotMatch(withoutComments, /storage\.buckets/);
});

test("new migration 20260712000000: sets meal-photos bucket to private and nothing else", () => {
  assert.match(bucketPrivateMigration, /update storage\.buckets/);
  assert.match(bucketPrivateMigration, /set public = false/);
  assert.match(bucketPrivateMigration, /where id = 'meal-photos'/);
  assert.doesNotMatch(bucketPrivateMigration, /create policy|drop policy/, "this migration should only touch the bucket row, policies are handled by the other migration");
});

test("migration filenames sort in chronological order matching their content order (recovered policy fix before the new bucket-privacy migration)", () => {
  const files = readdirSync(path.join(here, "migrations")).filter((name) => name.endsWith(".sql")).sort();
  assert.deepEqual(files, [
    "20260708041749_restrict_meal_photos_read_to_owner.sql",
    "20260712000000_set_meal_photos_bucket_private.sql",
  ]);
});

test("schema.sql and fix-meal-photos-storage-permissions.sql agree on the final private/owner-only shape (no drift between the two files)", () => {
  const schemaBlock = bucketInsertBlock(schemaSql);
  const fixBlock = bucketInsertBlock(fixSql);
  assert.equal(schemaBlock.includes("false,"), fixBlock.includes("false,"));
  for (const name of ["meal_photos_read_own", "meal_photos_authenticated_insert_own", "meal_photos_authenticated_update_own", "meal_photos_authenticated_delete_own"]) {
    assert.equal(schemaSql.includes(`create policy "${name}"`), fixSql.includes(`create policy "${name}"`), `policy "${name}" presence must match between the two files`);
  }
});
