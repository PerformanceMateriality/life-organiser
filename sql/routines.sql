-- Life Organiser — routines, logs and rest days
-- Reconstructed from the live database on 2026-09-22. Idempotent: safe to run
-- twice, and safe to run against the existing database (it will change nothing).
-- Covers builds 1–8, including the columns added later by ALTER.

create table if not exists public.routines (
  id           uuid primary key default gen_random_uuid(),
  name         text        not null,
  category     text        not null,
  cadence      text        not null,
  target       text,
  unit         text,
  track_value  boolean     not null default false,
  active       boolean     not null default true,
  sort_order   integer     not null default 0,
  created_at   timestamptz not null default now(),
  target_value numeric
);
-- added after the table existed (numeric targets)
alter table public.routines add column if not exists target_value numeric;

-- Build 15. Two features used to find their routine by regex on the NAME: the gym
-- tracker auto-ticked whatever matched /gym/i, and the body-weight trend card read
-- whatever matched /weigh/i. Renaming either routine in the in-app editor silently
-- killed the feature — no error, nothing to notice. `role` is a stable handle that
-- survives a rename.
alter table public.routines add column if not exists role text;

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'routines_role_check' and conrelid = 'public.routines'::regclass
  ) then
    alter table public.routines add constraint routines_role_check
      check (role is null or role = any (array['gym'::text, 'weigh'::text]));
  end if;
end $$;

-- At most one routine per role, so the lookup can never be ambiguous.
create unique index if not exists routines_role_key on public.routines (role) where role is not null;

-- Backfill from the names the regexes were matching, so nothing changes behaviour on
-- the day this runs. Only fills a role that is still unclaimed.
update public.routines set role = 'gym'
where role is null and name ~* 'gym'
  and not exists (select 1 from public.routines where role = 'gym');

update public.routines set role = 'weigh'
where role is null and track_value and name ~* 'weigh'
  and not exists (select 1 from public.routines where role = 'weigh');

create table if not exists public.routine_logs (
  id         uuid primary key default gen_random_uuid(),
  routine_id uuid        not null references public.routines(id) on delete cascade,
  log_date   date        not null,
  completed  boolean     not null default true,
  value      numeric,
  created_at timestamptz not null default now(),
  note       text
);
-- added after the table existed (per-day notes)
alter table public.routine_logs add column if not exists note text;

-- One log row per routine per day. The app relies on this for upsert-style writes.
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'routine_logs_routine_id_log_date_key'
      and conrelid = 'public.routine_logs'::regclass
  ) then
    alter table public.routine_logs
      add constraint routine_logs_routine_id_log_date_key unique (routine_id, log_date);
  end if;
end $$;

create index if not exists idx_routine_logs_date    on public.routine_logs using btree (log_date);
create index if not exists idx_routine_logs_routine on public.routine_logs using btree (routine_id);

create table if not exists public.rest_days (
  day        date primary key,
  note       text,
  created_at timestamptz not null default now()
);

-- Grants. New tables created through the SQL editor do NOT inherit these, which is
-- why they are spelled out — that lesson is in §6 of the project reference.
--
-- `anon` is deliberately absent: the app never touches REST before sign-in, so an
-- unauthenticated grant bought nothing and left RLS as the only guard on a key that
-- is published in a public repo. Revoked 2026-09-23.
--
-- `service_role` reads these three to build reminder messages — it is pg_cron, which
-- has no user session, so it needs the grant and bypasses RLS. The gym and tasks
-- tables get no service_role grant, because nothing server-side reads them.
grant all on table public.routines     to authenticated, service_role;
grant all on table public.routine_logs to authenticated, service_role;
grant all on table public.rest_days    to authenticated, service_role;

-- RLS: authenticated-only. Single user, so this is a lock on the front door rather
-- than row-level isolation.
alter table public.routines     enable row level security;
alter table public.routine_logs enable row level security;
alter table public.rest_days    enable row level security;

drop policy if exists "authed routines" on public.routines;
create policy "authed routines" on public.routines
  for all to authenticated using (true) with check (true);

drop policy if exists "authed routine_logs" on public.routine_logs;
create policy "authed routine_logs" on public.routine_logs
  for all to authenticated using (true) with check (true);

drop policy if exists "authed rest_days" on public.rest_days;
create policy "authed rest_days" on public.rest_days
  for all to authenticated using (true) with check (true);
