-- Daily stock sync for Master Mac Food: re-scrape stonyhill.mastermacfood.com
-- and hide any product that is out of stock on their site (and re-show anything
-- back in stock). Calls the sync-mastermac-stock edge function once a day.
--
-- Runs at 10:00 UTC (05:00 America/Jamaica) — early morning, before the day's
-- ordering. verify_jwt is off on the function, so the publishable key is enough
-- to pass the gateway; the function itself uses the service role from its own
-- environment to update menus.availability.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('mastermac_stock_daily')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'mastermac_stock_daily');

    PERFORM cron.schedule(
      'mastermac_stock_daily',
      '0 10 * * *',
      $cron$
      SELECT net.http_post(
        url     := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/sync-mastermac-stock',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', 'sb_publishable_Wws-3041OFpgbbNuh140Rw_AgZR5P52',
          'Authorization', 'Bearer sb_publishable_Wws-3041OFpgbbNuh140Rw_AgZR5P52'
        ),
        body    := '{}'::jsonb,
        timeout_milliseconds := 300000
      );
      $cron$
    );
  END IF;
END $$;
