-- Build 32: the "coach me" tool (food-mcp get_coach_data) reads the gym tables.
-- Edge Functions use service_role, which until now had no SELECT on them (sql/gym.sql:
-- "no service_role grant, because nothing server-side reads them"). Read-only on purpose:
-- coaching never writes gym data. Idempotent: re-granting is a no-op.
grant select on table public.gym_workouts  to service_role;
grant select on table public.gym_sets      to service_role;
grant select on table public.gym_exercises to service_role;
