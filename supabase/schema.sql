do $$
begin
  if not exists (select 1 from pg_type where typname = 'meal_type') then
    create type public.meal_type as enum ('breakfast', 'lunch', 'dinner', 'snack');
  end if;
end $$;

create table if not exists public.food_items (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  source_id text,
  eaten_on date not null,
  meal public.meal_type not null,
  name text not null,
  grams numeric not null default 0 check (grams >= 0),
  calories numeric not null default 0 check (calories >= 0),
  protein numeric not null default 0 check (protein >= 0),
  carbs numeric not null default 0 check (carbs >= 0),
  fat numeric not null default 0 check (fat >= 0),
  fiber numeric not null default 0 check (fiber >= 0),
  note text,
  photo_urls text[] not null default '{}',
  created_at timestamptz not null default now()
);

create unique index if not exists food_items_user_source_uidx
on public.food_items (user_id, source_id)
where source_id is not null;

create index if not exists food_items_user_eaten_on_idx
on public.food_items (user_id, eaten_on desc, created_at asc);

create index if not exists food_items_user_meal_idx
on public.food_items (user_id, meal);

grant usage on schema public to authenticated;
grant usage on type public.meal_type to authenticated;
grant select, insert, update, delete on public.food_items to authenticated;

alter table public.food_items enable row level security;

drop policy if exists "food_items_select_own" on public.food_items;
drop policy if exists "food_items_insert_own" on public.food_items;
drop policy if exists "food_items_update_own" on public.food_items;
drop policy if exists "food_items_delete_own" on public.food_items;
drop policy if exists "temporary_read_all_food_items" on public.food_items;
drop policy if exists "temporary_insert_all_food_items" on public.food_items;
drop policy if exists "temporary_update_all_food_items" on public.food_items;
drop policy if exists "temporary_delete_all_food_items" on public.food_items;

create policy "food_items_select_own"
on public.food_items for select
using ((select auth.uid()) = user_id);

create policy "food_items_insert_own"
on public.food_items for insert
with check ((select auth.uid()) = user_id);

create policy "food_items_update_own"
on public.food_items for update
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "food_items_delete_own"
on public.food_items for delete
using ((select auth.uid()) = user_id);

create table if not exists public.body_metrics (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  measured_on date not null,
  measured_at timestamptz,
  score numeric not null default 0 check (score >= 0),
  weight_kg numeric not null default 0 check (weight_kg >= 0),
  bmi numeric not null default 0 check (bmi >= 0),
  body_fat_percent numeric not null default 0 check (body_fat_percent >= 0),
  body_age numeric not null default 0 check (body_age >= 0),
  body_type text,
  muscle_kg numeric not null default 0 check (muscle_kg >= 0),
  skeletal_muscle_kg numeric not null default 0 check (skeletal_muscle_kg >= 0),
  bone_mass_kg numeric not null default 0 check (bone_mass_kg >= 0),
  water_percent numeric not null default 0 check (water_percent >= 0),
  visceral_fat numeric not null default 0 check (visceral_fat >= 0),
  bmr_kcal numeric not null default 0 check (bmr_kcal >= 0),
  protein_percent numeric not null default 0 check (protein_percent >= 0),
  trunk_fat_percent numeric not null default 0 check (trunk_fat_percent >= 0),
  trunk_muscle_kg numeric not null default 0 check (trunk_muscle_kg >= 0),
  left_arm_fat_percent numeric not null default 0 check (left_arm_fat_percent >= 0),
  left_arm_muscle_kg numeric not null default 0 check (left_arm_muscle_kg >= 0),
  right_arm_fat_percent numeric not null default 0 check (right_arm_fat_percent >= 0),
  right_arm_muscle_kg numeric not null default 0 check (right_arm_muscle_kg >= 0),
  left_leg_fat_percent numeric not null default 0 check (left_leg_fat_percent >= 0),
  left_leg_muscle_kg numeric not null default 0 check (left_leg_muscle_kg >= 0),
  right_leg_fat_percent numeric not null default 0 check (right_leg_fat_percent >= 0),
  right_leg_muscle_kg numeric not null default 0 check (right_leg_muscle_kg >= 0),
  note text,
  created_at timestamptz not null default now()
);

alter table public.body_metrics
  add column if not exists trunk_fat_percent numeric not null default 0 check (trunk_fat_percent >= 0),
  add column if not exists trunk_muscle_kg numeric not null default 0 check (trunk_muscle_kg >= 0),
  add column if not exists left_arm_fat_percent numeric not null default 0 check (left_arm_fat_percent >= 0),
  add column if not exists left_arm_muscle_kg numeric not null default 0 check (left_arm_muscle_kg >= 0),
  add column if not exists right_arm_fat_percent numeric not null default 0 check (right_arm_fat_percent >= 0),
  add column if not exists right_arm_muscle_kg numeric not null default 0 check (right_arm_muscle_kg >= 0),
  add column if not exists left_leg_fat_percent numeric not null default 0 check (left_leg_fat_percent >= 0),
  add column if not exists left_leg_muscle_kg numeric not null default 0 check (left_leg_muscle_kg >= 0),
  add column if not exists right_leg_fat_percent numeric not null default 0 check (right_leg_fat_percent >= 0),
  add column if not exists right_leg_muscle_kg numeric not null default 0 check (right_leg_muscle_kg >= 0);

create unique index if not exists body_metrics_user_measured_on_uidx
on public.body_metrics (user_id, measured_on);

create index if not exists body_metrics_user_measured_on_idx
on public.body_metrics (user_id, measured_on desc);

grant select, insert, update, delete on public.body_metrics to authenticated;

alter table public.body_metrics enable row level security;

drop policy if exists "body_metrics_select_own" on public.body_metrics;
drop policy if exists "body_metrics_insert_own" on public.body_metrics;
drop policy if exists "body_metrics_update_own" on public.body_metrics;
drop policy if exists "body_metrics_delete_own" on public.body_metrics;

create policy "body_metrics_select_own"
on public.body_metrics for select
using ((select auth.uid()) = user_id);

create policy "body_metrics_insert_own"
on public.body_metrics for insert
with check ((select auth.uid()) = user_id);

create policy "body_metrics_update_own"
on public.body_metrics for update
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "body_metrics_delete_own"
on public.body_metrics for delete
using ((select auth.uid()) = user_id);

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

create table if not exists public.daily_activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  activity_on date not null,
  source text not null default 'manual',
  steps numeric not null default 0 check (steps >= 0),
  active_calories numeric not null default 0 check (active_calories >= 0),
  total_calories numeric not null default 0 check (total_calories >= 0),
  exercise_minutes numeric not null default 0 check (exercise_minutes >= 0),
  stand_hours numeric not null default 0 check (stand_hours >= 0),
  distance_km numeric not null default 0 check (distance_km >= 0),
  floors numeric not null default 0 check (floors >= 0),
  resting_heart_rate numeric not null default 0 check (resting_heart_rate >= 0),
  hrv_ms numeric not null default 0 check (hrv_ms >= 0),
  sleep_minutes numeric not null default 0 check (sleep_minutes >= 0),
  raw_metrics jsonb not null default '{}'::jsonb,
  note text,
  created_at timestamptz not null default now()
);

alter table public.daily_activities
  add column if not exists raw_metrics jsonb not null default '{}'::jsonb;

create unique index if not exists daily_activities_user_date_source_uidx
on public.daily_activities (user_id, activity_on, source);

create index if not exists daily_activities_user_date_idx
on public.daily_activities (user_id, activity_on desc);

grant select, insert, update, delete on public.daily_activities to authenticated;

alter table public.daily_activities enable row level security;

drop policy if exists "daily_activities_select_own" on public.daily_activities;
drop policy if exists "daily_activities_insert_own" on public.daily_activities;
drop policy if exists "daily_activities_update_own" on public.daily_activities;
drop policy if exists "daily_activities_delete_own" on public.daily_activities;

create policy "daily_activities_select_own"
on public.daily_activities for select
using ((select auth.uid()) = user_id);

create policy "daily_activities_insert_own"
on public.daily_activities for insert
with check ((select auth.uid()) = user_id);

create policy "daily_activities_update_own"
on public.daily_activities for update
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "daily_activities_delete_own"
on public.daily_activities for delete
using ((select auth.uid()) = user_id);

create table if not exists public.exercise_activities (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade default auth.uid(),
  activity_on date not null,
  started_at timestamptz,
  source text not null default 'manual',
  external_id text,
  type text not null default '其他',
  title text not null default '运动',
  duration_minutes numeric not null default 0 check (duration_minutes >= 0),
  distance_km numeric not null default 0 check (distance_km >= 0),
  active_calories numeric not null default 0 check (active_calories >= 0),
  avg_heart_rate numeric not null default 0 check (avg_heart_rate >= 0),
  max_heart_rate numeric not null default 0 check (max_heart_rate >= 0),
  elevation_gain_m numeric not null default 0 check (elevation_gain_m >= 0),
  note text,
  created_at timestamptz not null default now()
);

drop index if exists public.exercise_activities_user_source_external_uidx;

create unique index if not exists exercise_activities_user_source_external_uidx
on public.exercise_activities (user_id, source, external_id);

create index if not exists exercise_activities_user_date_idx
on public.exercise_activities (user_id, activity_on desc, started_at desc);

grant select, insert, update, delete on public.exercise_activities to authenticated;

alter table public.exercise_activities enable row level security;

drop policy if exists "exercise_activities_select_own" on public.exercise_activities;
drop policy if exists "exercise_activities_insert_own" on public.exercise_activities;
drop policy if exists "exercise_activities_update_own" on public.exercise_activities;
drop policy if exists "exercise_activities_delete_own" on public.exercise_activities;

create policy "exercise_activities_select_own"
on public.exercise_activities for select
using ((select auth.uid()) = user_id);

create policy "exercise_activities_insert_own"
on public.exercise_activities for insert
with check ((select auth.uid()) = user_id);

create policy "exercise_activities_update_own"
on public.exercise_activities for update
using ((select auth.uid()) = user_id)
with check ((select auth.uid()) = user_id);

create policy "exercise_activities_delete_own"
on public.exercise_activities for delete
using ((select auth.uid()) = user_id);
