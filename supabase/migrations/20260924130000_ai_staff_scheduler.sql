-- ============================================================================
-- HotBite AI Staff — Stage 7: daily scheduler
-- ============================================================================
-- Reuses the project's existing pg_cron + net.http_post + Vault pattern (the
-- same one automation-workflow-runner / daily-birthday-wishes use). An hourly
-- cron calls a dispatcher that fires the pipeline ONCE on the configured
-- America/Jamaica hour, after operations close.
--
-- Safety:
--   * Configurable run hour via app_config (no cron edit needed to change it).
--   * Overlap-safe: a session advisory lock stops two dispatches colliding.
--   * Duplicate-safe: skips if a run already exists for the Jamaica day (and the
--     report/briefing functions themselves upsert by date).
--   * NOT active until verified: ai_staff_enabled defaults to 'false'. The cron
--     is deployed but no-ops until an operator flips the flag after verifying.
--   * No secret in this file: the bearer is read from Vault (automation_runner_secret).
--   * Operational log records only scheduler events (date/hour/outcome) — no
--     customer data and no keys.
-- ============================================================================

-- ── config (defaults; both editable by admin in app_config) ──
INSERT INTO public.app_config (key, value) VALUES
  ('ai_staff_enabled', 'false'),                 -- master on/off; stays false until verified
  ('ai_staff_run_hour_jamaica', '23')            -- 23:00 Jamaica = after close (configurable)
ON CONFLICT (key) DO NOTHING;

-- ── scheduler operational log (no PII, no secrets) ──
CREATE TABLE IF NOT EXISTS public.ai_staff_scheduler_log (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  created_at     timestamptz NOT NULL DEFAULT now(),
  jamaica_date   date,
  jamaica_hour   int,
  action         text NOT NULL,   -- dispatched | skipped_disabled | skipped_hour | skipped_duplicate | locked_out | error
  detail         text,
  http_request_id bigint
);
CREATE INDEX IF NOT EXISTS idx_ai_staff_scheduler_log_created ON public.ai_staff_scheduler_log(created_at DESC);

ALTER TABLE public.ai_staff_scheduler_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ai_staff_scheduler_log_admin_read ON public.ai_staff_scheduler_log;
CREATE POLICY ai_staff_scheduler_log_admin_read ON public.ai_staff_scheduler_log
  FOR SELECT TO authenticated USING (public.is_admin());
GRANT SELECT ON public.ai_staff_scheduler_log TO authenticated;

-- ── dispatcher ──
CREATE OR REPLACE FUNCTION public.run_ai_staff_daily(p_force boolean DEFAULT false)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_enabled   boolean;
  v_hour_cfg  int;
  v_jd        date;
  v_jh        int;
  v_secret    text;
  v_url       text := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/ai-staff-daily-report';
  v_req       bigint;
  v_action    text;
BEGIN
  -- Overlap guard: if another dispatch holds the lock, stand down.
  IF NOT pg_try_advisory_lock(hashtext('ai_staff_daily')) THEN
    INSERT INTO ai_staff_scheduler_log(action, detail) VALUES ('locked_out', 'another dispatch in progress');
    RETURN 'locked_out';
  END IF;

  v_jd := (now() AT TIME ZONE 'America/Jamaica')::date;
  v_jh := EXTRACT(HOUR FROM (now() AT TIME ZONE 'America/Jamaica'))::int;

  SELECT (value = 'true') INTO v_enabled FROM app_config WHERE key = 'ai_staff_enabled';
  SELECT COALESCE(NULLIF(value,'')::int, 23) INTO v_hour_cfg FROM app_config WHERE key = 'ai_staff_run_hour_jamaica';

  IF NOT p_force THEN
    IF COALESCE(v_enabled, false) = false THEN
      INSERT INTO ai_staff_scheduler_log(jamaica_date, jamaica_hour, action) VALUES (v_jd, v_jh, 'skipped_disabled');
      PERFORM pg_advisory_unlock(hashtext('ai_staff_daily'));
      RETURN 'skipped_disabled';
    END IF;
    IF v_jh <> COALESCE(v_hour_cfg, 23) THEN
      -- Hourly cron: only the configured Jamaica hour proceeds.
      PERFORM pg_advisory_unlock(hashtext('ai_staff_daily'));
      RETURN 'skipped_hour';
    END IF;
    -- Duplicate guard: one pipeline per Jamaica business day.
    IF EXISTS (SELECT 1 FROM ai_report_runs WHERE report_date = v_jd AND status IN ('running','completed','partial')) THEN
      INSERT INTO ai_staff_scheduler_log(jamaica_date, jamaica_hour, action) VALUES (v_jd, v_jh, 'skipped_duplicate');
      PERFORM pg_advisory_unlock(hashtext('ai_staff_daily'));
      RETURN 'skipped_duplicate';
    END IF;
  END IF;

  SELECT decrypted_secret INTO v_secret FROM vault.decrypted_secrets WHERE name = 'automation_runner_secret';
  IF v_secret IS NULL THEN
    INSERT INTO ai_staff_scheduler_log(jamaica_date, jamaica_hour, action, detail)
      VALUES (v_jd, v_jh, 'error', 'automation_runner_secret not found in vault');
    PERFORM pg_advisory_unlock(hashtext('ai_staff_daily'));
    RETURN 'error_no_secret';
  END IF;

  -- Fire the pipeline: staff reports, then the combined briefing.
  SELECT net.http_post(
    url := v_url,
    headers := jsonb_build_object('Authorization', 'Bearer ' || v_secret, 'Content-Type', 'application/json'),
    body := jsonb_build_object('report_date', v_jd::text, 'triggered_by',
              CASE WHEN p_force THEN 'manual' ELSE 'cron' END, 'run_briefing', true)
  ) INTO v_req;

  v_action := CASE WHEN p_force THEN 'dispatched_manual' ELSE 'dispatched' END;
  INSERT INTO ai_staff_scheduler_log(jamaica_date, jamaica_hour, action, http_request_id)
    VALUES (v_jd, v_jh, v_action, v_req);

  PERFORM pg_advisory_unlock(hashtext('ai_staff_daily'));
  RETURN v_action || ' (request ' || v_req || ')';
END;
$fn$;

REVOKE ALL ON FUNCTION public.run_ai_staff_daily(boolean) FROM PUBLIC, anon;

-- ── schedule: hourly; the dispatcher gates to the configured Jamaica hour ──
SELECT cron.unschedule('ai-staff-daily') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'ai-staff-daily');
SELECT cron.schedule('ai-staff-daily', '0 * * * *', $$SELECT public.run_ai_staff_daily();$$);

NOTIFY pgrst, 'reload schema';
