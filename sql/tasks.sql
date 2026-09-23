-- Life Organiser — tasks (build 13)
-- Reconstructed from the live database on 2026-09-22. Idempotent.
-- This already ran successfully on 2026-09-21; the file exists so the schema is in
-- version control rather than only in a chat attachment.
--
-- One list, two kinds. To-dos get ticked and may be undated; appointments must sit
-- on a day and pass on their own rather than being completed.

create table if not exists public.tasks (
  id         uuid primary key default gen_random_uuid(),
  title      text        not null,
  kind       text        not null default 'todo',
  due_date   date,
  due_time   time,
  end_time   time,
  location   text,
  note       text,
  done       boolean     not null default false,
  done_at    timestamptz,
  sort_order integer     not null default 0,
  created_at timestamptz not null default now()
);

do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_kind_check' and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks add constraint tasks_kind_check
      check (kind = any (array['todo'::text, 'appt'::text]));
  end if;
  -- An appointment without a day can't be drawn anywhere, so the database refuses it.
  if not exists (
    select 1 from pg_constraint
    where conname = 'tasks_appt_needs_date' and conrelid = 'public.tasks'::regclass
  ) then
    alter table public.tasks add constraint tasks_appt_needs_date
      check ((kind <> 'appt'::text) or (due_date is not null));
  end if;
end $$;

create index if not exists tasks_due_date_idx on public.tasks using btree (due_date);
create index if not exists tasks_kind_idx     on public.tasks using btree (kind);
create index if not exists tasks_done_idx     on public.tasks using btree (done);

-- `anon` revoked 2026-09-23. No service_role grant: reminders deliberately cover
-- routines only, so nothing server-side reads tasks. See sql/README.md.
grant all on table public.tasks to authenticated;

alter table public.tasks enable row level security;

drop policy if exists "tasks_all_authenticated" on public.tasks;
create policy "tasks_all_authenticated" on public.tasks
  for all to authenticated using (true) with check (true);
