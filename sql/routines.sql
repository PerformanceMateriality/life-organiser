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
