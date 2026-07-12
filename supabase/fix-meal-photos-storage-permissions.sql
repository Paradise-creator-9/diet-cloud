-- Historical "fix" script for environments that ran an old copy of this
-- file (or an old schema.sql) with a public bucket and an unrestricted
-- read policy. Content now matches supabase/schema.sql's storage section
-- exactly (both must stay in sync) and is safe to re-run any number of
-- times: it only ever ends in the private, owner-scoped state below,
-- regardless of what policy/bucket state existed before.
--
-- meal-photos is a PRIVATE bucket: photos are read through per-user,
-- per-folder policies below, never through the public object URL. Object
-- paths are always written by the app as `${userId}/${date}/${fileName}`
-- (see src/supabase.ts, api/ingest.js), so `(storage.foldername(name))[1]`
-- is always the owning user's auth.uid() and is what every policy checks.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'meal-photos',
  'meal-photos',
  false,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'image/heif']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "meal_photos_public_read" on storage.objects;
drop policy if exists "meal_photos_read_own" on storage.objects;
drop policy if exists "meal_photos_authenticated_insert_own" on storage.objects;
drop policy if exists "meal_photos_authenticated_update_own" on storage.objects;
drop policy if exists "meal_photos_authenticated_delete_own" on storage.objects;

create policy "meal_photos_read_own"
on storage.objects for select
to authenticated
using (
  bucket_id = 'meal-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "meal_photos_authenticated_insert_own"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'meal-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "meal_photos_authenticated_update_own"
on storage.objects for update to authenticated
using (
  bucket_id = 'meal-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
)
with check (
  bucket_id = 'meal-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);

create policy "meal_photos_authenticated_delete_own"
on storage.objects for delete to authenticated
using (
  bucket_id = 'meal-photos'
  and (storage.foldername(name))[1] = (select auth.uid())::text
);
