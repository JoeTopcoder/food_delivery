-- Migration: the remaining three dashboard RPCs — live ops, SLA attribution,
-- and partner leaderboards. Admin-gated and revoked from PUBLIC, as the others.

-- ── 4. Orders in flight, and how close they are to the SLA ─────────────────
-- Buckets come from sla_warning_thresholds in app_config rather than being
-- written into the query, so moving the SLA does not need a migration.
-- Counts are returned with their own labels rather than as columns named
-- bucket_30_35, because the edges come from config: the moment someone
-- retunes sla_warning_thresholds, fixed column names would quietly describe
-- the wrong ranges. The UI renders whatever labels come back.
DROP FUNCTION IF EXISTS public.admin_live_ops();
CREATE OR REPLACE FUNCTION public.admin_live_ops()
RETURNS TABLE (
  status         TEXT,
  orders_count   BIGINT,
  bucket_labels  TEXT[],
  bucket_counts  BIGINT[],
  breach_count   BIGINT,
  oldest_minutes NUMERIC
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_b NUMERIC[];
  v_l TEXT[];
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;

  BEGIN
    v_b := string_to_array(
      COALESCE((SELECT value FROM public.app_config
                 WHERE key = 'sla_warning_thresholds'), '30,35,40,45'), ',')::numeric[];
  EXCEPTION WHEN OTHERS THEN
    v_b := NULL;
  END;
  -- Anything that is not four ascending numbers falls back, so the buckets
  -- stay meaningful even if the config is edited to nonsense.
  IF v_b IS NULL OR array_length(v_b, 1) IS DISTINCT FROM 4
     OR NOT (v_b[1] < v_b[2] AND v_b[2] < v_b[3] AND v_b[3] < v_b[4]) THEN
    v_b := ARRAY[30,35,40,45]::numeric[];
  END IF;

  v_l := ARRAY[
    '0-'      || trim_scale(v_b[1])::text,
    trim_scale(v_b[1])::text || '-' || trim_scale(v_b[2])::text,
    trim_scale(v_b[2])::text || '-' || trim_scale(v_b[3])::text,
    trim_scale(v_b[3])::text || '-' || trim_scale(v_b[4])::text,
    trim_scale(v_b[4])::text || '+'
  ];

  RETURN QUERY
  WITH inflight AS (
    SELECT o.status AS st,
           EXTRACT(EPOCH FROM (now() - o.ordered_at)) / 60.0 AS age_min
    FROM public.orders o
    -- In flight means placed and not yet finished. delivered and cancelled
    -- are terminal; everything before them is still someone's problem.
    WHERE o.status NOT IN ('delivered', 'cancelled')
      AND o.ordered_at IS NOT NULL
  )
  SELECT i.st,
         count(*)::bigint,
         v_l,
         ARRAY[
           count(*) FILTER (WHERE i.age_min <  v_b[1]),
           count(*) FILTER (WHERE i.age_min >= v_b[1] AND i.age_min < v_b[2]),
           count(*) FILTER (WHERE i.age_min >= v_b[2] AND i.age_min < v_b[3]),
           count(*) FILTER (WHERE i.age_min >= v_b[3] AND i.age_min < v_b[4]),
           count(*) FILTER (WHERE i.age_min >= v_b[4])
         ]::bigint[],
         -- Past the last threshold is the only bucket that is unambiguously
         -- a breach; the ones before it are warnings.
         count(*) FILTER (WHERE i.age_min >= v_b[4])::bigint,
         ROUND(MAX(i.age_min)::numeric, 1)
  FROM inflight i
  GROUP BY i.st
  ORDER BY i.st;
END;
$fn$;

-- ── 5. Where the time goes ─────────────────────────────────────────────────
-- Time in a stage is the gap between one status event and the next, charged
-- to the actor who OWNED the earlier stage — the store owns the wait between
-- "confirmed" and "picked up", not the rider who ends it.
--
-- This reads order_status_events, which only started recording on
-- 2026-09-09. Orders placed before that have no events at all, so early
-- numbers are thin. sample_size is returned so the dashboard can say how
-- little it is standing on instead of presenting an average of two as fact.
CREATE OR REPLACE FUNCTION public.admin_sla_attribution(
  p_period TEXT DEFAULT 'today',
  p_from   TIMESTAMPTZ DEFAULT NULL,
  p_to     TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  actor_type        TEXT,
  avg_minutes       NUMERIC,
  median_minutes    NUMERIC,
  p90_minutes       NUMERIC,
  max_minutes       NUMERIC,
  sample_size       BIGINT,
  share_of_time_pct NUMERIC
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_from TIMESTAMPTZ;
  v_to   TIMESTAMPTZ;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  SELECT r_from, r_to INTO v_from, v_to
    FROM public.admin_period_range(p_period, p_from, p_to);

  RETURN QUERY
  WITH steps AS (
    SELECT e.actor_type AS actor,
           e.occurred_at,
           LEAD(e.occurred_at) OVER (
             PARTITION BY e.order_id ORDER BY e.occurred_at, e.id) AS next_at
    FROM public.order_status_events e
    WHERE e.occurred_at >= v_from AND e.occurred_at < v_to
      AND e.actor_type IS NOT NULL
  ),
  durations AS (
    -- The last event of an order in flight has no successor. Counting it as
    -- zero would flatter whoever is currently holding the order, so it is
    -- left out until the stage actually closes.
    SELECT s.actor,
           EXTRACT(EPOCH FROM (s.next_at - s.occurred_at)) / 60.0 AS minutes
    FROM steps s
    WHERE s.next_at IS NOT NULL
  ),
  total AS (SELECT NULLIF(SUM(d.minutes), 0) AS t FROM durations d)
  SELECT d.actor,
         ROUND(AVG(d.minutes)::numeric, 1),
         ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY d.minutes)::numeric, 1),
         ROUND(PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY d.minutes)::numeric, 1),
         ROUND(MAX(d.minutes)::numeric, 1),
         count(*)::bigint,
         ROUND((SUM(d.minutes) / (SELECT t FROM total) * 100)::numeric, 1)
  FROM durations d
  GROUP BY d.actor
  ORDER BY 7 DESC NULLS LAST;
END;
$fn$;

-- ── 6. Leaderboards ────────────────────────────────────────────────────────
-- Contribution and GMV come from admin_order_economics, the same helper the
-- KPI cards use, so a partner's contribution here adds up to the total shown
-- there instead of being a second, subtly different definition of the word.
CREATE OR REPLACE FUNCTION public.admin_top_partners(
  p_period TEXT DEFAULT 'mtd',
  p_kind   TEXT DEFAULT 'restaurant',
  p_limit  INT  DEFAULT 10,
  p_from   TIMESTAMPTZ DEFAULT NULL,
  p_to     TIMESTAMPTZ DEFAULT NULL
)
RETURNS TABLE (
  partner_id      UUID,
  partner_name    TEXT,
  orders_count    BIGINT,
  gmv             BIGINT,
  contribution    BIGINT,
  delivered_count BIGINT,
  on_time_pct     NUMERIC
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_from TIMESTAMPTZ;
  v_to   TIMESTAMPTZ;
  v_sla  NUMERIC;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  IF p_kind NOT IN ('restaurant', 'supermarket', 'rider') THEN
    RAISE EXCEPTION 'Invalid kind %. Use restaurant, supermarket or rider', p_kind;
  END IF;
  -- Clamped, not trusted: an unbounded limit from the client is a way to make
  -- the server do arbitrary work.
  p_limit := LEAST(GREATEST(COALESCE(p_limit, 10), 1), 100);

  SELECT r_from, r_to INTO v_from, v_to
    FROM public.admin_period_range(p_period, p_from, p_to);
  v_sla := COALESCE(NULLIF((SELECT value FROM public.app_config
                             WHERE key = 'grocery_sla_minutes'), '')::numeric, 45);

  RETURN QUERY
  WITH econ AS (
    -- Riders work both verticals, so their board spans both halves; a store
    -- board takes only its own.
    SELECT * FROM public.admin_order_economics(v_from, v_to, TRUE)
     WHERE p_kind IN ('supermarket', 'rider')
    UNION ALL
    SELECT * FROM public.admin_order_economics(v_from, v_to, FALSE)
     WHERE p_kind IN ('restaurant', 'rider')
  ),
  scoped AS (
    SELECT CASE WHEN p_kind = 'rider' THEN d.user_id ELSE o.restaurant_id END AS pid,
           CASE WHEN p_kind = 'rider' THEN COALESCE(u.name, 'Driver')
                ELSE r.name END AS pname,
           e.gmv,
           e.commission + e.delivery_fee + e.service_fee - e.rider_payout AS contrib,
           o.ordered_at,
           o.delivered_at
    FROM econ e
    JOIN public.orders o      ON o.id = e.order_id
    JOIN public.restaurants r ON r.id = o.restaurant_id
    LEFT JOIN public.drivers d ON d.id = o.driver_id
    LEFT JOIN public.users   u ON u.id = d.user_id
    -- orders.driver_id references drivers.id, not users.id; the board is keyed
    -- on the user so it lines up with every other place a rider is named.
    WHERE p_kind <> 'rider' OR d.user_id IS NOT NULL
  )
  SELECT s.pid,
         s.pname,
         count(*)::bigint,
         COALESCE(sum(s.gmv), 0)::bigint,
         COALESCE(sum(s.contrib), 0)::bigint,
         count(*) FILTER (WHERE s.delivered_at IS NOT NULL)::bigint,
         -- On-time needs a delivered_at to measure against. Orders without one
         -- are left out of the rate rather than counted late: absent is not
         -- slow. delivered_count is returned alongside so a 100% built on one
         -- order is visible as such.
         CASE WHEN count(*) FILTER (WHERE s.delivered_at IS NOT NULL) > 0
              THEN ROUND(
                (count(*) FILTER (
                   WHERE s.delivered_at IS NOT NULL
                     AND EXTRACT(EPOCH FROM (s.delivered_at - s.ordered_at)) / 60.0 <= v_sla
                 )::numeric
                 / count(*) FILTER (WHERE s.delivered_at IS NOT NULL)) * 100, 1)
              ELSE NULL END
  FROM scoped s
  GROUP BY s.pid, s.pname
  ORDER BY 5 DESC, 3 DESC
  LIMIT p_limit;
END;
$fn$;

DO $grants$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('admin_live_ops', 'admin_sla_attribution', 'admin_top_partners')
  LOOP
    -- PUBLIC, not anon: the default EXECUTE grant lives on PUBLIC and anon
    -- inherits it, so revoking anon alone changes nothing.
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END
$grants$;

NOTIFY pgrst, 'reload schema';
