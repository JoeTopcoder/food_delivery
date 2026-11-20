-- Real-time driver online status. Previously `is_online` only changed via the
-- on/off toggle, so a driver who closed the app (without toggling) stayed
-- "online" forever (e.g. one driver online since Oct 5). Add a heartbeat the
-- driver app pings while online, and auto-flip stale drivers offline.

ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS last_seen timestamptz;

INSERT INTO public.app_config (key, value, value_type)
VALUES ('driver_online_stale_minutes', '5', 'string')
ON CONFLICT (key) DO NOTHING;

-- Heartbeat: the signed-in driver marks themselves alive. Called ~every 60s
-- while the driver is online. Keeps is_online true and refreshes last_seen.
CREATE OR REPLACE FUNCTION public.driver_heartbeat()
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  UPDATE public.drivers SET last_seen = now()
  WHERE user_id = auth.uid();
END;
$$;
REVOKE ALL ON FUNCTION public.driver_heartbeat() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_heartbeat() TO authenticated;

-- Flip drivers offline when their heartbeat has gone stale (or never sent).
CREATE OR REPLACE FUNCTION public.reconcile_stale_drivers_offline()
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_mins numeric; v_cnt int;
BEGIN
  SELECT COALESCE((SELECT NULLIF(value,'')::numeric FROM public.app_config WHERE key='driver_online_stale_minutes'), 5)
    INTO v_mins;
  UPDATE public.drivers
     SET is_online = false, is_available = false, updated_at = now()
   WHERE is_online = true
     AND (last_seen IS NULL OR last_seen < now() - make_interval(mins => v_mins::int));
  GET DIAGNOSTICS v_cnt = ROW_COUNT;
  RETURN v_cnt;
END;
$$;
REVOKE ALL ON FUNCTION public.reconcile_stale_drivers_offline() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.reconcile_stale_drivers_offline() TO authenticated;

-- Admin overview self-heals: reconcile stale drivers, then count. Now VOLATILE
-- (it writes). Keeps the "Online riders" KPI honest every ~20s the admin views.
CREATE OR REPLACE FUNCTION public.admin_overview_stats(p_period text DEFAULT 'today')
RETURNS jsonb
LANGUAGE plpgsql VOLATILE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  v_from timestamptz;
  v_to   timestamptz;
  v_all  boolean := false;
  v_rev  numeric; v_ord bigint; v_riders bigint; v_stores bigint;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden: admin only'; END IF;

  PERFORM public.reconcile_stale_drivers_offline();

  v_to := ((now() AT TIME ZONE 'America/Jamaica')::date + 1)::timestamp AT TIME ZONE 'America/Jamaica';
  IF p_period = 'today' THEN
    v_from := ((now() AT TIME ZONE 'America/Jamaica')::date)::timestamp AT TIME ZONE 'America/Jamaica';
  ELSIF p_period = '7d' THEN
    v_from := (((now() AT TIME ZONE 'America/Jamaica')::date) - 6)::timestamp AT TIME ZONE 'America/Jamaica';
  ELSIF p_period = '30d' THEN
    v_from := (((now() AT TIME ZONE 'America/Jamaica')::date) - 29)::timestamp AT TIME ZONE 'America/Jamaica';
  ELSE
    v_all := true;
  END IF;

  SELECT COALESCE(sum(total_amount),0) INTO v_rev FROM orders
   WHERE status='delivered' AND (v_all OR (delivered_at >= v_from AND delivered_at < v_to));
  SELECT count(*) INTO v_ord FROM orders
   WHERE (v_all OR (ordered_at >= v_from AND ordered_at < v_to));
  SELECT count(*) INTO v_riders FROM drivers WHERE is_online = true;
  SELECT count(*) INTO v_stores FROM restaurants WHERE is_verified = true;

  RETURN jsonb_build_object('period', p_period, 'revenue', round(v_rev,2),
    'orders', v_ord, 'online_riders', v_riders, 'active_stores', v_stores);
END;
$fn$;
REVOKE ALL ON FUNCTION public.admin_overview_stats(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_overview_stats(text) TO authenticated;

-- Clean up existing stuck-online drivers right now.
SELECT public.reconcile_stale_drivers_offline() AS flipped_offline;

NOTIFY pgrst, 'reload schema';
