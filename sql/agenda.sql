-- Life Organiser — agenda mirror + planning via Claude (build 27). Idempotent.
--
-- Appointments live in his iPhone Agenda, and the app stops competing with it: an iOS
-- Shortcuts automation sends the next 14 days of his PRIVATE calendars to the
-- `agenda-sync` Edge Function, which mirrors them here. The app shows them read-only
-- alongside his tasks. Work calendars stay out (his choice, 2026-10-26).
--
-- calendar_events is a mirror, not his data: the real events live in iCloud, so each
-- sync replaces the synced window. Days before the window are kept as history.

create table if not exists public.calendar_events (
  id         uuid        primary key default gen_random_uuid(),
  start_at   timestamptz not null,
  end_at     timestamptz,
  all_day    boolean     not null default false,
  title      text        not null,
  location   text,
  calendar   text,
  synced_at  timestamptz not null default now()
);
create index if not exists calendar_events_start_idx on public.calendar_events (start_at);

revoke all on table public.calendar_events from anon;
grant all on table public.calendar_events to authenticated, service_role;
alter table public.calendar_events enable row level security;
drop policy if exists "authed calendar_events" on public.calendar_events;
create policy "authed calendar_events" on public.calendar_events
  for all to authenticated using (true) with check (true);

-- The evening check-in (food-mcp) now also adds to-dos and reads tomorrow's plan, so
-- the service role needs the tasks table (sql/tasks.sql carries the same grant).
grant all on table public.tasks to service_role;

-- "Plan tomorrow" gets its rename-proof role, so the check-in can tick it.
update public.routines set role = 'plan'
where role is null and name ~* '\mplan\M'
  and not exists (select 1 from public.routines where role = 'plan');
