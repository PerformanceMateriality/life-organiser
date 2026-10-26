-- Life Organiser — food log (build 24). Idempotent: safe to run twice.
--
-- Written by the `food-mcp` Edge Function, which Claude calls as a custom connector:
-- Martijn describes his day in a Claude chat, Claude estimates the macros and logs them
-- here. Nothing is weighed; these are estimates, roughly ±20% on mixed meals.
--
-- The function runs with the service role key (Claude has no user session), so both
-- tables need the service_role grant, the same trap as sql/reminders.sql.

-- One row per game day (the day runs until 02:00, same as the app). Claude sends the
-- whole day each time, so a re-log replaces the row; the version it replaced is kept in
-- `previous`, so a bad re-log can be undone by hand.
create table if not exists public.food_days (
  day            date        primary key,
  kcal           integer     not null default 0 check (kcal between 0 and 20000),
  protein_g      numeric(6,1) not null default 0 check (protein_g >= 0),
  carbs_g        numeric(6,1) not null default 0 check (carbs_g >= 0),
  fat_g          numeric(6,1) not null default 0 check (fat_g >= 0),
  fiber_g        numeric(6,1) not null default 0 check (fiber_g >= 0),
  alcohol_units  numeric(4,1) not null default 0 check (alcohol_units >= 0),  -- standard drinks, 10 g alcohol each
  water_ml       integer     not null default 0 check (water_ml >= 0),
  caffeine_mg    integer     not null default 0 check (caffeine_mg >= 0),
  -- [{ name, amount, kcal, protein_g, carbs_g, fat_g, fiber_g, staple? }]
  items          jsonb       not null default '[]'::jsonb,
  description    text,       -- what he said, verbatim, so an estimate can be redone later
  note           text,       -- Claude's caveats ("portion of pasta guessed at 100 g dry")
  previous       jsonb,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);

-- His regular foods with fixed numbers, so repeat meals stop being guesses.
-- Keyed by a lowercase name ("usual breakfast", "protein shake").
create table if not exists public.food_staples (
  name        text        primary key check (name = lower(name) and length(name) between 1 and 60),
  portion     text        not null,          -- "3 eggs, 2 slices rye, coffee with milk"
  kcal        integer     not null default 0 check (kcal >= 0),
  protein_g   numeric(6,1) not null default 0 check (protein_g >= 0),
  carbs_g     numeric(6,1) not null default 0 check (carbs_g >= 0),
  fat_g       numeric(6,1) not null default 0 check (fat_g >= 0),
  fiber_g     numeric(6,1) not null default 0 check (fiber_g >= 0),
  retired     boolean     not null default false,   -- retire beats delete
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Grants. `anon` deliberately absent, as everywhere else — and revoked explicitly,
-- because Supabase's default privileges grant it on every new table (found 2026-10-26).
revoke all on table public.food_days    from anon;
revoke all on table public.food_staples from anon;
grant all on table public.food_days    to authenticated, service_role;
grant all on table public.food_staples to authenticated, service_role;

alter table public.food_days    enable row level security;
alter table public.food_staples enable row level security;

drop policy if exists "authed food_days" on public.food_days;
create policy "authed food_days" on public.food_days
  for all to authenticated using (true) with check (true);

drop policy if exists "authed food_staples" on public.food_staples;
create policy "authed food_staples" on public.food_staples
  for all to authenticated using (true) with check (true);

-- ---------------------------------------------------------------- build 24: routines
-- The Log food tile, and roles for the three tiles the food log fills. Same role list
-- as sql/routines.sql (repeated so this file runs on its own).
alter table public.routines drop constraint if exists routines_role_check;
alter table public.routines add constraint routines_role_check
  check (role is null or role = any (array['gym','weigh','food','protein','fiber','water','plan']));

-- Log food: ticks itself when Claude logs the day. target_value = the calorie target:
-- 2,200 kcal (2026-10-26). Recomp, small deficit. Maintenance ≈ 2,350: BMR 1,780
-- (Mifflin-St Jeor, 173 cm / 31 / 85 kg) × 1.2 for ~4,200 steps a day, + ~150/day for
-- 3–4 weight sessions of 45–60 min, + ~50/day for 3 × 30 min easy treadmill walks.
-- Retune after 2–3 weeks of logs against the weight trend.
insert into public.routines (name, category, cadence, track_value, active, sort_order, role, target_value, unit)
select 'Log food', 'health', 'daily', false, true,
       coalesce((select max(sort_order) from public.routines where category = 'health'), 0) + 1,
       'food', 2200, 'kcal'
where not exists (select 1 from public.routines where role = 'food');

update public.routines set role = 'protein'
where role is null and track_value and name ~* 'protein'
  and not exists (select 1 from public.routines where role = 'protein');
update public.routines set role = 'fiber'
where role is null and track_value and name ~* 'fib(er|re)'
  and not exists (select 1 from public.routines where role = 'fiber');
update public.routines set role = 'water'
where role is null and track_value and name ~* 'water|hydrat'
  and not exists (select 1 from public.routines where role = 'water');
