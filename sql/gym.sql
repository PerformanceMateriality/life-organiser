-- Life Organiser — gym tracker
-- Reconstructed from the live database on 2026-09-22. Idempotent.
--
-- This is the post-v2 schema: builds 10 and 11 collapsed into one file. The original
-- gym-setup.sql / gym-v2-setup.sql split was only ever a delivery sequence and the
-- files are gone, so the ALTERs below are what upgrades a build-10 database.
--
-- gym_exercises seeds itself from GYM_SEED in index.html on first load, so there are
-- deliberately no INSERTs here.

create table if not exists public.gym_exercises (
  id          uuid primary key default gen_random_uuid(),
  name        text        not null,
  muscle      text,
  in_template text,                              -- 'A' | 'B' | null
  is_extra    boolean     not null default false,
  sort_order  integer     not null default 0,
  active      boolean     not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists public.gym_workouts (
  id           uuid primary key default gen_random_uuid(),
  workout_date date        not null,
  label        text,
  note         text,
  created_at   timestamptz not null default now(),
  finished     boolean     not null default true,
  ex_order     jsonb,
  ex_notes     jsonb
);
-- Build 11 (live persistence) added these three. The default on `finished` is true
-- for the benefit of build-10 rows; the app always writes finished:false on start.
alter table public.gym_workouts add column if not exists finished boolean not null default true;
alter table public.gym_workouts add column if not exists ex_order jsonb;
alter table public.gym_workouts add column if not exists ex_notes jsonb;

create table if not exists public.gym_sets (
  id          uuid primary key default gen_random_uuid(),
  workout_id  uuid        not null references public.gym_workouts(id) on delete cascade,
  exercise_id uuid        references public.gym_exercises(id) on delete set null,
  set_no      integer     not null default 1,
  weight      numeric,
  reps        integer,
  created_at  timestamptz not null default now()
);

-- Deleting a workout takes its sets with it; deleting an exercise from the library
-- keeps the sets and orphans the reference, so history is never destroyed.
do $$ begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'gym_sets_workout_id_fkey' and conrelid = 'public.gym_sets'::regclass
  ) then
    alter table public.gym_sets add constraint gym_sets_workout_id_fkey
      foreign key (workout_id) references public.gym_workouts(id) on delete cascade;
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'gym_sets_exercise_id_fkey' and conrelid = 'public.gym_sets'::regclass
  ) then
    alter table public.gym_sets add constraint gym_sets_exercise_id_fkey
      foreign key (exercise_id) references public.gym_exercises(id) on delete set null;
  end if;
end $$;

create index if not exists gym_sets_workout_idx  on public.gym_sets using btree (workout_id);
create index if not exists gym_sets_exercise_idx on public.gym_sets using btree (exercise_id);

-- `anon` revoked 2026-09-23; no service_role grant, because nothing server-side
-- reads the gym tables. See sql/README.md.
grant all on table public.gym_exercises to authenticated;
grant all on table public.gym_workouts  to authenticated;
grant all on table public.gym_sets      to authenticated;

alter table public.gym_exercises enable row level security;
alter table public.gym_workouts  enable row level security;
alter table public.gym_sets      enable row level security;

drop policy if exists "auth all" on public.gym_exercises;
create policy "auth all" on public.gym_exercises
  for all to authenticated using (true) with check (true);

drop policy if exists "auth all" on public.gym_workouts;
create policy "auth all" on public.gym_workouts
  for all to authenticated using (true) with check (true);

drop policy if exists "auth all" on public.gym_sets;
create policy "auth all" on public.gym_sets
  for all to authenticated using (true) with check (true);
