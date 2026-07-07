grant usage on schema public to service_role;

alter table public.daily_activities
  add column if not exists raw_metrics jsonb not null default '{}'::jsonb;

create unique index if not exists daily_activities_user_date_source_uidx
on public.daily_activities (user_id, activity_on, source);

grant select, insert, update, delete on public.daily_activities to service_role;
grant select, insert, update, delete on public.exercise_activities to service_role;

update public.exercise_activities
set external_id = 'manual-' || id::text
where external_id is null;

drop index if exists public.exercise_activities_user_source_external_uidx;

create unique index if not exists exercise_activities_user_source_external_uidx
on public.exercise_activities (user_id, source, external_id);
