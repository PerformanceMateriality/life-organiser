-- Life Organiser — the reminders schedule (build 14)
--
-- Run this LAST: after sql/reminders.sql, after the `reminders` Edge Function is
-- deployed, and after the private push key is in the function's secrets. A job that fires
-- against a missing function just logs failures every 15 minutes.
--
-- Every 15 minutes it pokes the function in `cron` mode. The function decides whether
-- any slot is actually due (within CATCHUP_MIN = 120 minutes of its time) and whether
-- it has anything to say. A run with nothing to do is a no-op, so the frequency is
-- about not missing a slot, not about sending often.
--
-- ⚠️ REPLACE <SERVICE_ROLE_KEY> below with the service role key from
--    Supabase → Project Settings → API. Do not paste that key into a chat.
--    It is stored in the `cron.job` table, readable by anyone with database access —
--    which for this project is Martijn alone. Supabase Vault is the tidier option if
--    that ever stops being true.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Re-running this replaces the existing job of the same name rather than adding a
-- second one, so the file stays idempotent like the rest of sql/.
select cron.schedule(
  'life-organiser-reminders',
  '*/15 * * * *',
  $job$
  select net.http_post(
    url     := 'https://ncxictnhhmnexhmvqvhd.supabase.co/functions/v1/reminders',
    headers := '{"Content-Type":"application/json","Authorization":"Bearer <SERVICE_ROLE_KEY>"}'::jsonb,
    body    := '{"mode":"cron"}'::jsonb
  );
  $job$
);

-- Check it landed:
--   select jobid, jobname, schedule, active from cron.job;
--
-- See what the last runs did (pg_net logs the response separately):
--   select * from cron.job_run_details order by start_time desc limit 10;
--   select id, status_code, content from net._http_response order by created desc limit 10;
--
-- Turn it off without deleting it:
--   update cron.job set active = false where jobname = 'life-organiser-reminders';
--
-- Remove it entirely:
--   select cron.unschedule('life-organiser-reminders');
