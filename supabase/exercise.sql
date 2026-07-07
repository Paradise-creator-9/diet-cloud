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
