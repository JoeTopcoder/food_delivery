-- Schedule daily release of pending earnings whose hold period has elapsed.
-- Runs at 02:00 UTC every day via pg_cron.
-- This replicates the logic in the release-available-earnings Edge Function
-- but avoids needing secrets in SQL.

CREATE EXTENSION IF NOT EXISTS pg_cron;

-- Remove any existing schedule for this job (idempotent)
SELECT cron.unschedule('release-available-earnings')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'release-available-earnings'
);

SELECT cron.schedule(
  'release-available-earnings',
  '0 2 * * *',
  $$
    UPDATE public.earnings_ledger
    SET status = 'available', updated_at = now()
    WHERE status = 'pending'
      AND available_at <= now();
  $$
);
