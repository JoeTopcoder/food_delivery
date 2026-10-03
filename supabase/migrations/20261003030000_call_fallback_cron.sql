-- Durable timeout worker for call fallback: reconciles abandoned/stuck sessions
-- and enforces max bridge duration. Runs every minute (deadlines are >=90s / 5min
-- so minute granularity is sufficient; the 15s/10s connect timers are handled
-- client-side and request fallback explicitly).
DO $$
BEGIN
  PERFORM cron.unschedule('call_fallback_reconcile')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname='call_fallback_reconcile');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

SELECT cron.schedule('call_fallback_reconcile', '* * * * *',
  $$SELECT public.cf_reconcile_deadlines()$$);

NOTIFY pgrst, 'reload schema';
