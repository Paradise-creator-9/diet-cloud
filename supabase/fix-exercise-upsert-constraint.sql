update public.exercise_activities
set external_id = 'manual-' || id::text
where external_id is null;

drop index if exists public.exercise_activities_user_source_external_uidx;

create unique index if not exists exercise_activities_user_source_external_uidx
on public.exercise_activities (user_id, source, external_id);
