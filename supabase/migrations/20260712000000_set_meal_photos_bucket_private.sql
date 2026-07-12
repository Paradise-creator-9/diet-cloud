-- New, forward migration authored in this repo on 2026-07-12 — not a
-- recovered historical migration. Production's meal-photos bucket is
-- currently storage.buckets.public = false (confirmed via a read-only
-- Supabase MCP query), but no migration in
-- supabase_migrations.schema_migrations ever set that flag, so it must
-- have been changed through some other, untracked action (most likely a
-- manual toggle in the Supabase Studio UI). This migration exists purely
-- to close that gap in version control: it makes the private-bucket state
-- explicit and reproducible from the repo alone, rather than depending on
-- an undocumented one-off action.
--
-- Idempotent: running this against production is a safe no-op (the bucket
-- is already private). Running it against a fresh project makes the
-- bucket private from the start, matching supabase/schema.sql.
--
-- Before applying any repo migration against the real production project,
-- reconcile local migration history with `supabase migration list`
-- (or an equivalent read-only check) first — this file's timestamp
-- (20260712000000) is later than the recovered
-- 20260708041749_restrict_meal_photos_read_to_owner migration, so it will
-- sort after it, but it has not been recorded as applied on production and
-- must not be run against production as part of this change.
update storage.buckets
set public = false
where id = 'meal-photos';
