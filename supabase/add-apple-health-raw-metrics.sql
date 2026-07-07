alter table public.daily_activities
  add column if not exists raw_metrics jsonb not null default '{}'::jsonb;
