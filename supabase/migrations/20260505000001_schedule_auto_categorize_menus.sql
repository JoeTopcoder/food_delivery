-- Schedule the `auto-categorize-menus` edge function to run once a day so any
-- newly added meals get tagged with the closest canonical home-screen
-- category (Pizza, Coffee, Chicken, ...) using the deterministic keyword
-- brain in supabase/functions/auto-categorize-menus/index.ts.
--
-- Requires the `pg_cron` and `pg_net` extensions (both available on Supabase).
-- The job calls the edge function over HTTP using the project's service role
-- key, which is read from the `app.settings.service_role_key` GUC if set,
-- otherwise from `current_setting('supabase.service_role_key', true)`.
--
-- To configure the secret once per project (run as a Supabase admin):
--   alter database postgres set app.settings.project_url   = 'https://<ref>.supabase.co';
--   alter database postgres set app.settings.service_role_key = '<service_role_key>';

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- Drop any previous schedule so re-running this migration is idempotent.
do $$
begin
  if exists (select 1 from cron.job where jobname = 'auto-categorize-menus-daily') then
    perform cron.unschedule('auto-categorize-menus-daily');
  end if;
end $$;

-- Run every day at 03:15 UTC (low-traffic window).
select cron.schedule(
  'auto-categorize-menus-daily',
  '15 3 * * *',
  $cron$
    select net.http_post(
      url := coalesce(
        current_setting('app.settings.project_url', true),
        'https://yharweliruemjexmuuxn.supabase.co'
      ) || '/functions/v1/auto-categorize-menus',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || coalesce(
          current_setting('app.settings.service_role_key', true),
          ''
        )
      ),
      body := jsonb_build_object('force', false)
    );
  $cron$
);
