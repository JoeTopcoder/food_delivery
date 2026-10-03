-- Admin overview KPIs for a selected period (America/Jamaica). Revenue and
-- order count respect the period; online riders and active stores are current
-- snapshots. Admin-only.
CREATE OR REPLACE FUNCTION public.admin_overview_stats(p_period text DEFAULT 'today')
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_from timestamptz;
  v_to   timestamptz := (now() AT TIME ZONE 'America/Jamaica')::date + 1;  -- placeholder
  v_all  boolean := false;
  v_rev  numeric;
  v_ord  bigint;
  v_riders bigint;
  v_stores bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden: admin only'; END IF;

  -- Resolve window in Jamaica time.
  v_to := ((now() AT TIME ZONE 'America/Jamaica')::date + 1)::timestamp AT TIME ZONE 'America/Jamaica';
  IF p_period = 'today' THEN
    v_from := ((now() AT TIME ZONE 'America/Jamaica')::date)::timestamp AT TIME ZONE 'America/Jamaica';
  ELSIF p_period = '7d' THEN
    v_from := (((now() AT TIME ZONE 'America/Jamaica')::date) - 6)::timestamp AT TIME ZONE 'America/Jamaica';
  ELSIF p_period = '30d' THEN
    v_from := (((now() AT TIME ZONE 'America/Jamaica')::date) - 29)::timestamp AT TIME ZONE 'America/Jamaica';
  ELSE
    v_all := true;  -- 'all'
  END IF;

  SELECT COALESCE(sum(total_amount),0) INTO v_rev
    FROM orders
   WHERE status='delivered'
     AND (v_all OR (delivered_at >= v_from AND delivered_at < v_to));

  SELECT count(*) INTO v_ord
    FROM orders
   WHERE (v_all OR (ordered_at >= v_from AND ordered_at < v_to));

  SELECT count(*) INTO v_riders FROM drivers WHERE is_online = true;
  SELECT count(*) INTO v_stores FROM restaurants WHERE is_verified = true;

  RETURN jsonb_build_object(
    'period', p_period,
    'revenue', round(v_rev,2),
    'orders', v_ord,
    'online_riders', v_riders,
    'active_stores', v_stores
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_overview_stats(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_overview_stats(text) TO authenticated;

NOTIFY pgrst, 'reload schema';
