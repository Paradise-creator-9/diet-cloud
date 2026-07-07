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
