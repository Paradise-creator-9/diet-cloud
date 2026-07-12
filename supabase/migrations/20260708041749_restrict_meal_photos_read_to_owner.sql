-- Recovered verbatim from the production project's
-- supabase_migrations.schema_migrations table (read-only query, via
-- Supabase MCP) on 2026-07-12 — this repo previously had no
-- supabase/migrations/ directory at all, so this migration existed only in
-- the live project's tracked history, not in version control. The
-- statements below are an exact copy, not a reconstruction.
--
-- This closed the public read policy on meal-photos: any authenticated
-- caller could previously read (but not enumerate) any user's photos via
-- storage.objects, since the old "meal_photos_public_read" policy had no
-- per-folder ownership check. It replaced that policy with one scoped to
-- the requesting user's own folder, matching the existing insert/update/
-- delete policies.
--
-- Note: this migration does NOT set storage.buckets.public = false — that
-- flag was already (or became) false on production through some other,
-- untracked action, not through this migration. See the following
-- migration file for a repo-tracked fix that closes that specific gap.
--
-- NOT idempotent (verified against a local Supabase instance on
-- 2026-07-12): re-running this file raw a second time fails with
-- `ERROR: policy "meal_photos_read_own" for table "objects" already
-- exists`, because the create policy statement has no matching
-- `drop policy if exists` guard for its own name (this is a verbatim
-- historical recovery, not a rewrite — see above). The failure is
-- non-destructive: the drop-if-exists statement no-ops safely and the
-- already-correct policy from the first run is left untouched, but this
-- file should not be re-applied outside of normal Supabase CLI migration
-- tracking (which only ever applies a given migration once).
drop policy if exists "meal_photos_public_read" on storage.objects;

create policy "meal_photos_read_own"
on storage.objects for select
to authenticated
using (
  bucket_id = 'meal-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
