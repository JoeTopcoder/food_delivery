-- Restaurant Pickup Coordinator — automatic dialing tick.
-- The DB "pickup-scan" cron enqueues due calls. This adds a tick that invokes
-- the edge function's dial_due action so the AI actually places the Agora calls.
-- Uses the service-role key from settings (same pattern as remind_stores).
CREATE OR REPLACE FUNCTION public.pickup_dial_tick()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _url text := coalesce(nullif(current_setting('app.settings.supabase_url', true), ''),
                        'https://yharweliruemjexmuuxn.supabase.co');
  _key text := nullif(current_setting('app.settings.service_role_key', true), '');
BEGIN
  IF _key IS NULL THEN
    -- No service key configured for automation; the queue still fills via
    -- pickup-scan and calls can be placed by invoking the function manually.
    RETURN;
  END IF;
  PERFORM extensions.http_post(
    url := _url || '/functions/v1/restaurant-pickup-coordinator',
    body := jsonb_build_object('action','dial_due')::text,
    headers := jsonb_build_object('Content-Type','application/json',
                                  'Authorization','Bearer ' || _key)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.pickup_dial_tick() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pickup_dial_tick() TO service_role;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
    PERFORM cron.unschedule('pickup-dial') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname='pickup-dial');
    PERFORM cron.schedule('pickup-dial', '*/3 * * * *', $c$ SELECT public.pickup_dial_tick(); $c$);
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
