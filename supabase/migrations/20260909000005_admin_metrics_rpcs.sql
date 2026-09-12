-- Migration: admin dashboard metrics RPCs (food, grocery, combined).
--
-- All SECURITY DEFINER, all gated on is_admin() — the helper that already
-- exists here and is keyed to auth.uid() — and all revoked from PUBLIC.
--
-- MONEY. The money columns on orders are double precision; converting them is
-- a breaking change across 92 columns and not this feature's job. So every
-- figure is cast to NUMERIC before any arithmetic and returned as BIGINT minor
-- units. No float math happens in aggregation and nothing crosses the wire as
-- a float.
--
-- Contribution is computed from primitives on every call. Nothing derived is
-- stored and there is no materialized view: at this order volume it would cost
-- more than it saves, and a stale cache on a dashboard is worse than a slow
-- query.

-- ── Resolve a period to a half-open range ──────────────────────────────────
-- Half-open [from, to) so an order at exactly midnight belongs to one period
-- rather than two. Bounds are computed in the platform's timezone, not UTC:
-- "today" has to mean today where the business actually is.
CREATE OR REPLACE FUNCTION public.admin_period_range(
  p_period TEXT,
  p_from   TIMESTAMPTZ DEFAULT NULL,
  p_to     TIMESTAMPTZ DEFAULT NULL,
  OUT r_from TIMESTAMPTZ,
  OUT r_to   TIMESTAMPTZ
)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_tz  TEXT := COALESCE(
    (SELECT value FROM public.app_config WHERE key = 'platform_timezone'),
    'America/Jamaica');
  v_now TIMESTAMP := (now() AT TIME ZONE v_tz);
BEGIN
  IF p_period NOT IN ('today','mtd','ytd','custom') THEN
    RAISE EXCEPTION 'Invalid period %. Use today, mtd, ytd or custom', p_period;
  END IF;

  IF p_period = 'custom' THEN
    IF p_from IS NULL OR p_to IS NULL THEN
      RAISE EXCEPTION 'A custom period requires both from and to';
    END IF;
    IF p_to <= p_from THEN
      RAISE EXCEPTION 'to must be after from';
    END IF;
    IF p_to - p_from > interval '2 years' THEN
      RAISE EXCEPTION 'A custom range cannot exceed 2 years';
    END IF;
    r_from := p_from;
    r_to   := p_to;
    RETURN;
  END IF;

  r_from := CASE p_period
              WHEN 'today' THEN date_trunc('day',   v_now)
              WHEN 'mtd'   THEN date_trunc('month', v_now)
              WHEN 'ytd'   THEN date_trunc('year',  v_now)
            END AT TIME ZONE v_tz;
  r_to := now();
END;
$fn$;

-- ── One row of order economics, in minor units ─────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_order_economics(
  p_from TIMESTAMPTZ, p_to TIMESTAMPTZ, p_grocery BOOLEAN
)
RETURNS TABLE (
  order_id     UUID,
  gmv          BIGINT,
  commission   BIGINT,
  delivery_fee BIGINT,
  service_fee  BIGINT,
  rider_payout BIGINT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT o.id,
         ROUND(COALESCE(o.subtotal, 0)::numeric * 100)::bigint,
         ROUND(COALESCE(o.commission_amount,
                        COALESCE(o.subtotal, 0) * COALESCE(o.commission_rate, 0)
               )::numeric * 100)::bigint,
         ROUND(COALESCE(o.delivery_fee, 0)::numeric * 100)::bigint,
         ROUND(COALESCE(o.platform_service_fee, 0)::numeric * 100)::bigint,
         -- Tips pass through to the rider and are not a platform cost, so they
         -- come out of payout rather than counting against contribution.
         GREATEST(
           ROUND((COALESCE(o.driver_total_pay, 0)
                - COALESCE(o.driver_tip, 0)
                - COALESCE(o.post_delivery_tip, 0))::numeric * 100)::bigint, 0)
  FROM public.orders o
  JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.ordered_at >= p_from
    AND o.ordered_at <  p_to
    AND o.status <> 'cancelled'
    AND (CASE WHEN p_grocery THEN r.store_type =  'grocery'
                             ELSE r.store_type <> 'grocery' END);
$fn$;

-- ── 1. Food ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_metrics_food(
  p_period TEXT DEFAULT 'today',
  p_from   TIMESTAMPTZ DEFAULT NULL,
  p_to     TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  orders_count                BIGINT,
  gmv                         BIGINT,
  restaurant_commission_total BIGINT,
  delivery_fee_total          BIGINT,
  rider_payout_total          BIGINT,
  contribution_total          BIGINT,
  avg_order_value             BIGINT,
  breakeven_orders_required   BIGINT,
  breakeven_progress_pct      NUMERIC
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_from TIMESTAMPTZ;
  v_to   TIMESTAMPTZ;
  v_ops  NUMERIC;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  SELECT * INTO v_from, v_to
    FROM public.admin_period_range(p_period, p_from, p_to);
  v_ops := COALESCE(
    (SELECT value FROM public.app_config WHERE key = 'monthly_ops_cost')::numeric, 0);

  RETURN QUERY
  WITH e AS (SELECT * FROM public.admin_order_economics(v_from, v_to, FALSE)),
  agg AS (
    SELECT count(*)::bigint                        AS n,
           COALESCE(sum(e.gmv), 0)::bigint          AS g,
           COALESCE(sum(e.commission), 0)::bigint   AS c,
           COALESCE(sum(e.delivery_fee), 0)::bigint AS d,
           COALESCE(sum(e.rider_payout), 0)::bigint AS p
    FROM e
  ),
  calc AS (
    SELECT agg.*,
           (agg.c + agg.d - agg.p) AS contrib,
           -- Break-even orders = monthly ops cost / contribution per order.
           -- Ops cost of zero means unconfigured, not free: return 0 rather
           -- than divide by nothing, and let the UI say it is unset.
           CASE WHEN v_ops > 0 AND agg.n > 0 AND (agg.c + agg.d - agg.p) > 0
                THEN CEIL((v_ops * 100)
                     / ((agg.c + agg.d - agg.p)::numeric / agg.n))::bigint
                ELSE 0::bigint END AS required
    FROM agg
  )
  SELECT calc.n, calc.g, calc.c, calc.d, calc.p, calc.contrib::bigint,
         CASE WHEN calc.n > 0 THEN (calc.g / calc.n)::bigint ELSE 0::bigint END,
         calc.required,
         CASE WHEN calc.required > 0
              THEN ROUND((calc.n::numeric / calc.required) * 100, 1)
              ELSE 0::numeric END
  FROM calc;
END;
$fn$;

-- ── 2. Grocery ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_metrics_grocery(
  p_period TEXT DEFAULT 'today',
  p_from   TIMESTAMPTZ DEFAULT NULL,
  p_to     TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  orders_count                 BIGINT,
  gmv                          BIGINT,
  service_fee_total            BIGINT,
  supermarket_commission_total BIGINT,
  delivery_fee_total           BIGINT,
  rider_payout_total           BIGINT,
  delivery_margin_total        BIGINT,
  contribution_total           BIGINT,
  avg_order_value              BIGINT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_from TIMESTAMPTZ;
  v_to   TIMESTAMPTZ;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  SELECT * INTO v_from, v_to
    FROM public.admin_period_range(p_period, p_from, p_to);

  RETURN QUERY
  WITH e AS (SELECT * FROM public.admin_order_economics(v_from, v_to, TRUE)),
  agg AS (
    SELECT count(*)::bigint                        AS n,
           COALESCE(sum(e.gmv), 0)::bigint          AS g,
           COALESCE(sum(e.service_fee), 0)::bigint  AS s,
           COALESCE(sum(e.commission), 0)::bigint   AS c,
           COALESCE(sum(e.delivery_fee), 0)::bigint AS d,
           COALESCE(sum(e.rider_payout), 0)::bigint AS p
    FROM e
  )
  SELECT agg.n, agg.g, agg.s, agg.c, agg.d, agg.p,
         (agg.d - agg.p)::bigint,
         (agg.s + agg.c + agg.d - agg.p)::bigint,
         CASE WHEN agg.n > 0 THEN (agg.g / agg.n)::bigint ELSE 0::bigint END
  FROM agg;
END;
$fn$;

-- ── 3. Combined ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_metrics_combined(
  p_period TEXT DEFAULT 'today',
  p_from   TIMESTAMPTZ DEFAULT NULL,
  p_to     TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  total_contribution BIGINT,
  ops_cost_prorated  BIGINT,
  operating_profit   BIGINT
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_from     TIMESTAMPTZ;
  v_to       TIMESTAMPTZ;
  v_ops      NUMERIC;
  v_days     NUMERIC;
  v_contrib  BIGINT;
  v_prorated BIGINT;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  SELECT * INTO v_from, v_to
    FROM public.admin_period_range(p_period, p_from, p_to);
  v_ops  := COALESCE(
    (SELECT value FROM public.app_config WHERE key = 'monthly_ops_cost')::numeric, 0);
  v_days := GREATEST(EXTRACT(EPOCH FROM (v_to - v_from)) / 86400.0, 0);

  SELECT COALESCE(f.contribution_total, 0) + COALESCE(g.contribution_total, 0)
    INTO v_contrib
  FROM public.admin_metrics_food(p_period, p_from, p_to)    AS f,
       public.admin_metrics_grocery(p_period, p_from, p_to) AS g;

  -- Ops cost is monthly; prorated over a 30-day month so a part-period profit
  -- figure is comparable to a full one.
  v_prorated := ROUND(v_ops * 100 * (v_days / 30.0))::bigint;

  RETURN QUERY SELECT v_contrib, v_prorated, (v_contrib - v_prorated)::bigint;
END;
$fn$;

-- ── Lock them down ─────────────────────────────────────────────────────────
DO $grants$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('admin_metrics_food','admin_metrics_grocery',
                        'admin_metrics_combined','admin_order_economics',
                        'admin_period_range')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END
$grants$;

NOTIFY pgrst, 'reload schema';
