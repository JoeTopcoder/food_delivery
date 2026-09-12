-- Migration: the four daily-target RPCs.
--
-- All SECURITY DEFINER, all gated on is_admin(), all revoked from PUBLIC.
-- All target math lives here; the client only renders what these return.

-- ── Config helpers, per vertical ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.target_cfg_num(p_key TEXT, p_vertical TEXT, p_default NUMERIC)
RETURNS NUMERIC LANGUAGE sql STABLE AS $fn$
  SELECT COALESCE(
    (SELECT NULLIF(btrim(value), '')::numeric
       FROM public.app_config WHERE key = p_key || '_' || p_vertical),
    p_default);
$fn$;

CREATE OR REPLACE FUNCTION public.target_cfg_bool(p_key TEXT, p_vertical TEXT, p_default BOOLEAN)
RETURNS BOOLEAN LANGUAGE sql STABLE AS $fn$
  SELECT COALESCE(
    (SELECT lower(btrim(value)) = 'true'
       FROM public.app_config WHERE key = p_key || '_' || p_vertical),
    p_default);
$fn$;

CREATE OR REPLACE FUNCTION public.platform_today()
RETURNS DATE LANGUAGE sql STABLE AS $fn$
  SELECT (now() AT TIME ZONE COALESCE(
    (SELECT value FROM public.app_config WHERE key = 'platform_timezone'),
    'America/Jamaica'))::date;
$fn$;

-- ── 1. Today's target with live progress ───────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_get_daily_target(
  p_target_date DATE DEFAULT NULL,
  p_vertical    TEXT DEFAULT 'food'
)
RETURNS TABLE (
  target_id                  BIGINT,
  target_date                DATE,
  vertical                   TEXT,
  target_orders              INT,
  source                     TEXT,
  notes                      TEXT,
  actual_orders              BIGINT,
  progress_pct               NUMERIC,
  projected_eod_orders       BIGINT,
  pace_status                TEXT,
  aov                        BIGINT,
  gross_revenue_per_order    BIGINT,
  net_contribution_per_order BIGINT,
  aov_delta_7d               BIGINT,
  gross_per_order_delta_7d   BIGINT,
  net_per_order_delta_7d     BIGINT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_date     DATE;
  v_tz       TEXT;
  v_elapsed  NUMERIC;
  v_is_today BOOLEAN;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  IF p_vertical NOT IN ('food','grocery') THEN
    RAISE EXCEPTION 'Invalid vertical %. Use food or grocery', p_vertical;
  END IF;

  v_tz   := COALESCE((SELECT value FROM public.app_config WHERE key='platform_timezone'),
                     'America/Jamaica');
  v_date := COALESCE(p_target_date, public.platform_today());
  v_is_today := (v_date = public.platform_today());

  -- Fraction of the day elapsed, in platform-local time. Used only to project
  -- a finishing pace, and only for today: projecting a past day is just its
  -- actual, and projecting a future day is fiction.
  v_elapsed := CASE
    WHEN NOT v_is_today THEN 1
    ELSE GREATEST(
      EXTRACT(EPOCH FROM ((now() AT TIME ZONE v_tz) - date_trunc('day', now() AT TIME ZONE v_tz)))
        / 86400.0,
      0.0001)   -- floor: at 00:00:01 a linear projection would divide by ~0
  END;

  RETURN QUERY
  WITH t AS (
    SELECT dt.id, dt.target_orders, dt.source, dt.notes
    FROM public.daily_targets dt
    WHERE dt.target_date = v_date AND dt.vertical = p_vertical
      AND dt.superseded_at IS NULL
    LIMIT 1
  ),
  a AS (
    SELECT da.orders_count, da.aov, da.gross_revenue_per_order,
           da.net_contribution_per_order
    FROM public.daily_actuals da
    WHERE da.target_date = v_date AND da.vertical = p_vertical
  ),
  -- Trailing 7 days, excluding today: comparing today's part-day averages
  -- against a window that includes them would flatten the delta toward zero.
  w AS (
    SELECT AVG(da.aov)                        AS aov,
           AVG(da.gross_revenue_per_order)    AS gross,
           AVG(da.net_contribution_per_order) AS net
    FROM public.daily_actuals da
    WHERE da.vertical = p_vertical
      AND da.target_date >= v_date - 7
      AND da.target_date <  v_date
      AND da.orders_count > 0
  )
  SELECT
    t.id,
    v_date,
    p_vertical,
    COALESCE(t.target_orders, 0),
    COALESCE(t.source, 'none'),
    t.notes,
    COALESCE(a.orders_count, 0),
    CASE WHEN COALESCE(t.target_orders,0) > 0
         THEN ROUND((COALESCE(a.orders_count,0)::numeric / t.target_orders) * 100, 1)
         ELSE 0 END,
    CASE WHEN v_is_today
         THEN FLOOR(COALESCE(a.orders_count,0) / v_elapsed)::bigint
         ELSE COALESCE(a.orders_count,0) END,
    CASE
      WHEN COALESCE(t.target_orders,0) = 0 THEN 'no_target'
      WHEN FLOOR(COALESCE(a.orders_count,0) / v_elapsed) >= t.target_orders THEN 'ahead'
      -- Within 10% of pace reads as on track; a strict comparison would call
      -- almost every moment of every day "behind".
      WHEN FLOOR(COALESCE(a.orders_count,0) / v_elapsed) >= t.target_orders * 0.9 THEN 'on_track'
      ELSE 'behind'
    END,
    COALESCE(a.aov, 0),
    COALESCE(a.gross_revenue_per_order, 0),
    COALESCE(a.net_contribution_per_order, 0),
    COALESCE(a.aov, 0) - COALESCE(ROUND(w.aov)::bigint, 0),
    COALESCE(a.gross_revenue_per_order, 0) - COALESCE(ROUND(w.gross)::bigint, 0),
    COALESCE(a.net_contribution_per_order, 0) - COALESCE(ROUND(w.net)::bigint, 0)
  FROM (SELECT 1) _
  LEFT JOIN t ON TRUE
  LEFT JOIN a ON TRUE
  LEFT JOIN w ON TRUE;
END;
$fn$;

-- ── 2. Manual override. Inserts; never updates. ────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_set_daily_target(
  p_target_date   DATE,
  p_vertical      TEXT,
  p_target_orders INT,
  p_notes         TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_admin UUID;
  v_prev  RECORD;
  v_id    BIGINT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  v_admin := auth.uid();

  IF p_vertical NOT IN ('food','grocery') THEN
    RAISE EXCEPTION 'Invalid vertical %. Use food or grocery', p_vertical;
  END IF;
  IF p_target_orders IS NULL OR p_target_orders < 0 THEN
    RAISE EXCEPTION 'Target must be zero or more';
  END IF;
  IF p_target_orders > 100000 THEN
    RAISE EXCEPTION 'Target of % is implausible; check the figure', p_target_orders;
  END IF;

  SELECT id, target_orders INTO v_prev
  FROM public.daily_targets
  WHERE target_date = p_target_date AND vertical = p_vertical
    AND superseded_at IS NULL;

  -- Retire the old row rather than editing it, so what was expected on a given
  -- day, and when that changed, stays readable.
  IF v_prev.id IS NOT NULL THEN
    UPDATE public.daily_targets SET superseded_at = now() WHERE id = v_prev.id;
  END IF;

  INSERT INTO public.daily_targets
    (target_date, vertical, target_orders, source, created_by,
     previous_target_id, notes)
  VALUES
    (p_target_date, p_vertical, p_target_orders, 'manual_override', v_admin,
     v_prev.id, p_notes)
  RETURNING id INTO v_id;

  INSERT INTO public.target_change_log
    (target_date, vertical, before_target, after_target, rule_applied,
     reasoning, actor, actor_id)
  VALUES
    (p_target_date, p_vertical, v_prev.target_orders, p_target_orders,
     'manual_override',
     jsonb_build_object('notes', p_notes, 'previous_target_id', v_prev.id),
     'admin', v_admin);

  RETURN v_id;
END;
$fn$;

-- ── 3. Propose tomorrow's target. Pure — writes nothing. ───────────────────
CREATE OR REPLACE FUNCTION public.admin_compute_next_target(
  p_for_date DATE,
  p_vertical TEXT
)
RETURNS TABLE (
  for_date          DATE,
  vertical          TEXT,
  previous_target   INT,
  previous_actual   BIGINT,
  hit               BOOLEAN,
  rule_applied      TEXT,
  raw_next          NUMERIC,
  proposed_target   INT,
  clamped_by        TEXT,
  reasoning         JSONB
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_prev_date DATE := p_for_date - 1;
  v_window    INT;
  v_growth    NUMERIC;
  v_hold      BOOLEAN;
  v_stepdown  NUMERIC;
  v_min       INT;
  v_maxjump   INT;
  v_prev_tgt  INT;
  v_actual    NUMERIC;
  v_hit       BOOLEAN;
  v_rule      TEXT;
  v_raw       NUMERIC;
  v_final     INT;
  v_clamp     TEXT := 'none';
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  IF p_vertical NOT IN ('food','grocery') THEN
    RAISE EXCEPTION 'Invalid vertical %. Use food or grocery', p_vertical;
  END IF;

  v_window   := GREATEST(public.target_cfg_num('target_smoothing_window_days', p_vertical, 1)::int, 1);
  v_growth   := public.target_cfg_num('target_growth_rate_on_hit', p_vertical, 0.05);
  v_hold     := public.target_cfg_bool('target_hold_on_miss', p_vertical, TRUE);
  v_stepdown := public.target_cfg_num('target_step_down_rate_on_miss', p_vertical, 0);
  v_min      := public.target_cfg_num('target_min', p_vertical, 1)::int;
  v_maxjump  := public.target_cfg_num('target_max_daily_increase', p_vertical, 5)::int;

  SELECT dt.target_orders INTO v_prev_tgt
  FROM public.daily_targets dt
  WHERE dt.target_date = v_prev_date AND dt.vertical = p_vertical
    AND dt.superseded_at IS NULL;

  -- Actual over the smoothing window: 1 day is literally yesterday, more is a
  -- moving average, so one freak day cannot ratchet the target.
  SELECT COALESCE(AVG(da.orders_count), 0) INTO v_actual
  FROM public.daily_actuals da
  WHERE da.vertical = p_vertical
    AND da.target_date >  v_prev_date - v_window
    AND da.target_date <= v_prev_date;

  -- No prior target is not a miss. Starting from the floor and letting the
  -- rule work from there is honest; treating it as a failure would step a new
  -- vertical down on its first day.
  IF v_prev_tgt IS NULL THEN
    v_hit  := NULL;
    v_rule := 'seed_no_prior_target';
    v_raw  := GREATEST(v_actual, v_min);
  ELSIF v_actual >= v_prev_tgt THEN
    v_hit  := TRUE;
    v_rule := 'growth_on_hit';
    v_raw  := v_prev_tgt * (1 + v_growth);
  ELSIF v_hold THEN
    v_hit  := FALSE;
    v_rule := 'hold_on_miss';
    v_raw  := v_prev_tgt;
  ELSE
    v_hit  := FALSE;
    v_rule := 'step_down_on_miss';
    v_raw  := v_prev_tgt * (1 - v_stepdown);
  END IF;

  v_final := CEIL(v_raw)::int;

  -- Ceiling on the absolute jump before the floor, so a large configured jump
  -- cannot push a target below the minimum on the way past it.
  IF v_prev_tgt IS NOT NULL AND v_final - v_prev_tgt > v_maxjump THEN
    v_final := v_prev_tgt + v_maxjump;
    v_clamp := 'max_daily_increase';
  END IF;
  IF v_final < v_min THEN
    v_final := v_min;
    v_clamp := CASE WHEN v_clamp = 'none' THEN 'min_target'
                    ELSE v_clamp || '+min_target' END;
  END IF;

  RETURN QUERY SELECT
    p_for_date, p_vertical, v_prev_tgt, ROUND(v_actual)::bigint, v_hit,
    v_rule, v_raw, v_final, v_clamp,
    jsonb_build_object(
      'previous_date',       v_prev_date,
      'smoothing_window_days', v_window,
      'growth_rate_on_hit',  v_growth,
      'hold_on_miss',        v_hold,
      'step_down_rate',      v_stepdown,
      'min_target',          v_min,
      'max_daily_increase',  v_maxjump,
      'actual_window_avg',   v_actual
    );
END;
$fn$;

-- ── 4. Apply it. Idempotent per (date, vertical). ──────────────────────────
CREATE OR REPLACE FUNCTION public.admin_apply_next_target(
  p_for_date DATE,
  p_vertical TEXT
)
RETURNS TABLE (target_id BIGINT, target_orders INT, source TEXT, created BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_existing RECORD;
  v_calc     RECORD;
  v_id       BIGINT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;

  SELECT dt.id, dt.target_orders, dt.source INTO v_existing
  FROM public.daily_targets dt
  WHERE dt.target_date = p_for_date AND dt.vertical = p_vertical
    AND dt.superseded_at IS NULL;

  -- Idempotent, and a manual override always survives the scheduler. Running
  -- the job twice must not produce a second row, and must never quietly
  -- replace a figure a human set on purpose.
  IF v_existing.id IS NOT NULL THEN
    RETURN QUERY SELECT v_existing.id, v_existing.target_orders,
                        v_existing.source, FALSE;
    RETURN;
  END IF;

  SELECT * INTO v_calc FROM public.admin_compute_next_target(p_for_date, p_vertical);

  INSERT INTO public.daily_targets
    (target_date, vertical, target_orders, source, previous_target_id, notes)
  VALUES
    (p_for_date, p_vertical, v_calc.proposed_target, 'auto',
     (SELECT id FROM public.daily_targets
       WHERE target_date = p_for_date - 1 AND vertical = p_vertical
         AND superseded_at IS NULL),
     v_calc.rule_applied)
  RETURNING id INTO v_id;

  INSERT INTO public.target_change_log
    (target_date, vertical, before_target, after_target, rule_applied,
     reasoning, actor)
  VALUES
    (p_for_date, p_vertical, v_calc.previous_target, v_calc.proposed_target,
     v_calc.rule_applied,
     v_calc.reasoning || jsonb_build_object('clamped_by', v_calc.clamped_by,
                                            'raw_next', v_calc.raw_next),
     'scheduler');

  RETURN QUERY SELECT v_id, v_calc.proposed_target, 'auto'::text, TRUE;
END;
$fn$;

-- ── Lock down ──────────────────────────────────────────────────────────────
DO $grants$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('admin_get_daily_target','admin_set_daily_target',
                        'admin_compute_next_target','admin_apply_next_target',
                        'target_cfg_num','target_cfg_bool','platform_today')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END
$grants$;

NOTIFY pgrst, 'reload schema';
