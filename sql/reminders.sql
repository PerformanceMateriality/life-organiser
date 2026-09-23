-- Life Organiser — reminders (build 14)
-- Idempotent: safe to run twice, and safe to re-run after the Edge Function exists.
--
-- Three tables. The column names are the client's contract, read out of the reminders
-- layer in index.html — `remDefaults()` seeds exactly these, `patchRem()` writes
-- <slot>_on / <slot>_time / enabled / skip_on_rest / updated_at, and `saveSub()` upserts
-- push_subscriptions on the endpoint. Renaming a column here breaks the app silently.
--
-- Unlike the other tables, these are read by the SERVER: pg_cron calls the reminders
-- Edge Function with the service role key, which has no user session and so bypasses
-- RLS. It needs explicit grants — that was the trap found on 2026-09-23, see
-- sql/README.md.

-- One row, id = 'default'. A single-user app has no reason to key this by user.
create table if not exists public.reminder_settings (
  id           text primary key,
  enabled      boolean     not null default true,
  skip_on_rest boolean     not null default true,   -- the sweep stays quiet on a rest day
  timezone     text        not null default 'Europe/Amsterdam',
  morning_on   boolean     not null default true,
  morning_time time        not null default '07:30',
  cadence_on   boolean     not null default true,
  cadence_time time        not null default '09:00',
  evening_on   boolean     not null default true,
  evening_time time        not null default '20:00',
  sweep_on     boolean     not null default true,
  sweep_time   time        not null default '21:30',
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);

-- Seed the row the server reads. The client also seeds it on first run; whichever
-- gets there first wins and the other is a no-op.
insert into public.reminder_settings (id) values ('default')
on conflict (id) do nothing;

-- One row per device that has accepted notifications. The endpoint is the identity:
-- the client upserts on it, and the function prunes rows the push service rejects.
create table if not exists public.push_subscriptions (
  id         uuid primary key default gen_random_uuid(),
  endpoint   text        not null,
  p256dh     text        not null,   -- without both keys a push cannot be encrypted,
  auth       text        not null,   -- so a row missing them would be dead weight
  user_agent text,
  last_seen  timestamptz not null default now(),
  created_at timestamptz not null default now()
);

-- Required by the client's `on_conflict=endpoint` upsert: PostgREST needs a real
-- unique constraint to resolve against, not just an index.
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'push_subscriptions_endpoint_key'
      and conrelid = 'public.push_subscriptions'::regclass
  ) then
    alter table public.push_subscriptions
      add constraint push_subscriptions_endpoint_key unique (endpoint);
  end if;
end $$;

-- The send ledger, and the thing that makes "one send per slot per day" true.
-- A slot is recorded even when it had nothing to say (silent = true), so that opening
-- the app later in the window can't replay it.
create table if not exists public.reminder_sends (
  id         uuid primary key default gen_random_uuid(),
  slot       text        not null,
  send_date  date        not null,
  sent_count integer     not null default 0,
  silent     boolean     not null default false,
  created_at timestamptz not null default now()
);

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'reminder_sends_slot_check'
      and conrelid = 'public.reminder_sends'::regclass
  ) then
    alter table public.reminder_sends add constraint reminder_sends_slot_check
      check (slot = any (array['morning'::text, 'cadence'::text, 'evening'::text, 'sweep'::text]));
  end if;
  -- The idempotency key for the whole scheme.
  if not exists (
    select 1 from pg_constraint
    where conname = 'reminder_sends_slot_send_date_key'
      and conrelid = 'public.reminder_sends'::regclass
  ) then
    alter table public.reminder_sends
      add constraint reminder_sends_slot_send_date_key unique (slot, send_date);
  end if;
end $$;

create index if not exists reminder_sends_date_idx on public.reminder_sends using btree (send_date desc);

-- Grants. `anon` deliberately absent, as everywhere else.
grant all on table public.reminder_settings  to authenticated, service_role;
grant all on table public.push_subscriptions to authenticated, service_role;
grant all on table public.reminder_sends     to authenticated, service_role;

alter table public.reminder_settings  enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.reminder_sends     enable row level security;

drop policy if exists "authed reminder_settings" on public.reminder_settings;
create policy "authed reminder_settings" on public.reminder_settings
  for all to authenticated using (true) with check (true);

drop policy if exists "authed push_subscriptions" on public.push_subscriptions;
create policy "authed push_subscriptions" on public.push_subscriptions
  for all to authenticated using (true) with check (true);

drop policy if exists "authed reminder_sends" on public.reminder_sends;
create policy "authed reminder_sends" on public.reminder_sends
  for all to authenticated using (true) with check (true);
