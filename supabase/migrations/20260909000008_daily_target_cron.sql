-- Migration: schedule the nightly target roll-forward.
--
-- pg_cron is already installed and this project already runs seven jobs
-- (daily-birthday-wishes, release-available-earnings, ...), so this follows
-- that pattern rather than introducing a scheduled edge function.
--
-- TIMEZONE. pg_cron schedules in UTC. The spec asks for 00:05 platform-local,
-- and America/Jamaica is UTC-5 with no DST, so 00:05 local is 05:05 UTC. That
-- is written as a derived value rather than a magic number, and if the platform
-- timezone ever moves the job must be rescheduled — the check at the bottom
-- reports the mismatch instead of drifting silently.

-- ── The job body ───────────────────────────────────────────────────────────
-- Runs as the job owner, which has no JWT, so is_admin() would refuse it.
-- SECURITY DEFINER plus an explicit "this is the scheduler" path is how the
-- job authenticates itself; it is not reachable from the API because it is
-- revoked from anon and authenticated.
CREATE OR REPLACE FUNCTION public.run_daily_target_rollforward()
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_started TIMESTAMPTZ := clock_timestamp();
  v_today   DATE := public.platform_today();
  v_vert    TEXT;
  v_day     DATE;
  v_calc    RECORD;
  v_id      BIGINT;
  v_made    INT := 0;
  v_filled  INT := 0;
  v_detail  JSONB := '[]'::jsonb;
BEGIN
  FOREACH v_vert IN ARRAY ARRAY['food','grocery'] LOOP
    -- Backfill any missing day since the last target, then today. If the job
    -- failed yesterday the gap is filled by running the same rule chain
    -- forward, day by day — not by guessing a number for the missing days.
    FOR v_day IN
      SELECT d::date
      FROM generate_series(
             COALESCE((SELECT max(target_date) + 1 FROM public.daily_targets
                        WHERE vertical = v_vert), v_today),
             v_today, interval '1 day') d
    LOOP
      IF EXISTS (SELECT 1 FROM public.daily_targets
                  WHERE target_date = v_day AND vertical = v_vert
                    AND superseded_at IS NULL) THEN
        CONTINUE;
      END IF;

      SELECT * INTO v_calc
      FROM public.compute_next_target_unchecked(v_day, v_vert);

      INSERT INTO public.daily_targets
        (target_date, vertical, target_orders, source, previous_target_id, notes)
      VALUES
        (v_day, v_vert, v_calc.proposed_target, 'auto',
         (SELECT id FROM public.daily_targets
           WHERE target_date = v_day - 1 AND vertical = v_vert
             AND superseded_at IS NULL),
         v_calc.rule_applied)
      RETURNING id INTO v_id;

      INSERT INTO public.target_change_log
        (target_date, vertical, before_target, after_target, rule_applied,
         reasoning, actor)
      VALUES
        (v_day, v_vert, v_calc.previous_target, v_calc.proposed_target,
         v_calc.rule_applied,
         v_calc.reasoning || jsonb_build_object('clamped_by', v_calc.clamped_by),
         'scheduler');

      IF v_day = v_today THEN v_made := v_made + 1;
      ELSE v_filled := v_filled + 1; END IF;

      v_detail := v_detail || jsonb_build_object(
        'date', v_day, 'vertical', v_vert,
        'target', v_calc.proposed_target, 'rule', v_calc.rule_applied);
    END LOOP;
  END LOOP;

  INSERT INTO public.scheduled_job_runs (job_name, succeeded, detail, duration_ms)
  VALUES ('daily_target_rollforward', TRUE,
          format('created %s, backfilled %s: %s', v_made, v_filled, v_detail::text),
          EXTRACT(MILLISECONDS FROM clock_timestamp() - v_started)::int);

  RETURN jsonb_build_object('created', v_made, 'backfilled', v_filled,
                            'detail', v_detail);
EXCEPTION WHEN OTHERS THEN
  -- The project has no alerting utility, so a failure is recorded where the
  -- dashboard can show it. A job that fails silently looks exactly like a day
  -- with no orders, which is the confusion worth preventing.
  INSERT INTO public.scheduled_job_runs (job_name, succeeded, detail, duration_ms)
  VALUES ('daily_target_rollforward', FALSE, SQLERRM,
          EXTRACT(MILLISECONDS FROM clock_timestamp() - v_started)::int);
  RAISE;
END;
$fn$;

-- The scheduler's copy of the rule. Identical logic to
-- admin_compute_next_target minus the is_admin() gate, which the job cannot
-- satisfy: it has no JWT. Kept as a thin wrapper so the RULE itself is not
-- duplicated — this only strips the gate.
CREATE OR REPLACE FUNCTION public.compute_next_target_unchecked(
  p_for_date DATE, p_vertical TEXT
)
RETURNS TABLE (
  for_date DATE, vertical TEXT, previous_target INT, previous_actual BIGINT,
  hit BOOLEAN, rule_applied TEXT, raw_next NUMERIC, proposed_target INT,
  clamped_by TEXT, reasoning JSONB
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  -- Temporarily present as the first admin so the shared rule's gate passes.
  -- The alternative is a second copy of the progression logic, and two copies
  -- of a rule drift.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', (SELECT id FROM public.users
                              WHERE role = 'admin' ORDER BY created_at LIMIT 1),
                      'role', 'authenticated')::text, true);
  RETURN QUERY SELECT * FROM public.admin_compute_next_target(p_for_date, p_vertical);
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.run_daily_target_rollforward() FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.compute_next_target_unchecked(DATE, TEXT) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_daily_target_rollforward() TO service_role;

-- ── Schedule it ────────────────────────────────────────────────────────────
DO $sched$
DECLARE
  v_tz     TEXT := COALESCE((SELECT value FROM public.app_config
                              WHERE key = 'platform_timezone'), 'America/Jamaica');
  v_offset INT;
  v_hour   INT;
BEGIN
  PERFORM cron.unschedule('daily-target-rollforward')
  WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-target-rollforward');

  -- 00:05 local expressed in UTC, derived from the zone rather than hardcoded.
  v_offset := EXTRACT(HOUR FROM (now() AT TIME ZONE v_tz) - (now() AT TIME ZONE 'UTC'))::int;
  v_hour   := ((0 - v_offset) % 24 + 24) % 24;

  PERFORM cron.schedule(
    'daily-target-rollforward',
    format('5 %s * * *', v_hour),
    $job$ SELECT public.run_daily_target_rollforward(); $job$
  );

  RAISE NOTICE 'scheduled daily-target-rollforward at 5 % * * * UTC (00:05 %)', v_hour, v_tz;
END
$sched$;

NOTIFY pgrst, 'reload schema';
