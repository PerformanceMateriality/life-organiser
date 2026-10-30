-- Life Organiser — projects (build 30). Idempotent.
--
-- A project groups to-dos ("Bruiloft", "Huis"). Optional date: a dated project counts
-- down on Today; an undated one only shows in Tasks. No XP (his answer, 2026-10-29).
-- Finishing a project archives it; nothing is deleted. Removing a project from a to-do
-- (or deleting a project by hand) leaves the to-do in place: on delete set null.

create table if not exists public.projects (
  id          uuid        primary key default gen_random_uuid(),
  name        text        not null check (length(name) between 1 and 60),
  color       text        not null default 'rose',
  due_date    date,
  archived_at timestamptz,
  created_at  timestamptz not null default now()
);

alter table public.tasks add column if not exists project_id uuid
  references public.projects(id) on delete set null;
create index if not exists tasks_project_idx on public.tasks (project_id);

-- Same as every other table: signed-in user and the service role (the evening check-in
-- in Claude adds to-dos to a project), never anon.
revoke all on table public.projects from anon;
grant all on table public.projects to authenticated, service_role;
alter table public.projects enable row level security;
drop policy if exists "authed projects" on public.projects;
create policy "authed projects" on public.projects
  for all to authenticated using (true) with check (true);
