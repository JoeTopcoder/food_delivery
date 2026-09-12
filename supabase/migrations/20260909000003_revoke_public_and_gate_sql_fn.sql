-- Migration: the anon revoke did nothing, and one SQL-language RPC is ungated.
--
-- Postgres grants EXECUTE on every new function to PUBLIC. anon is a member of
-- PUBLIC, so "REVOKE ... FROM anon" removed a grant anon never separately held
-- and changed nothing — the ACL still read {=X/postgres,...}, and =X is PUBLIC.
-- Revoking from PUBLIC is what actually takes it away.
--
-- admin_order_margins is LANGUAGE sql and so has no statement to gate; it is
-- rebuilt as plpgsql wrapping its own current body, so the behaviour is
-- carried over verbatim rather than retyped.

-- ── Actually take the admin surface away from the public ───────────────────
DO $revoke$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'admin_wallet_adjust','admin_order_margins','admin_survival_metrics',
        'admin_toggle_user_status','admin_verify_driver','admin_verify_restaurant',
        'admin_review_driver_application','get_analytics_summary',
        'get_platform_commission_summary','get_top_restaurants',
        'get_active_orders_summary','refresh_daily_metrics','refresh_user_metrics',
        'require_admin'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END
$revoke$;

-- ── Gate the SQL-language one by rewrapping its own body ───────────────────
DO $wrap$
DECLARE
  v_args TEXT;
  v_ret  TEXT;
  v_body TEXT;
BEGIN
  -- pg_get_function_arguments, not the identity form: the identity form
  -- strips DEFAULTs, and CREATE OR REPLACE cannot remove a default from an
  -- existing function.
  SELECT pg_get_function_arguments(p.oid),
         pg_get_function_result(p.oid),
         p.prosrc
    INTO v_args, v_ret, v_body
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
  WHERE n.nspname = 'public' AND p.proname = 'admin_order_margins'
    AND p.prosrc NOT ILIKE '%is_admin%';

  IF v_body IS NULL THEN
    RAISE NOTICE 'admin_order_margins already gated or missing — nothing to do';
    RETURN;
  END IF;

  EXECUTE format($fmt$
    CREATE OR REPLACE FUNCTION public.admin_order_margins(%s)
    RETURNS %s
    LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $body$
    BEGIN
      IF NOT public.is_admin() THEN
        RAISE EXCEPTION 'Forbidden: admin access required';
      END IF;
      RETURN QUERY %s;
    END;
    $body$;
  $fmt$, v_args, v_ret, btrim(v_body, E' 	
;'));

  REVOKE EXECUTE ON FUNCTION public.admin_order_margins(integer, integer) FROM PUBLIC;
  GRANT EXECUTE ON FUNCTION public.admin_order_margins(integer, integer)
    TO authenticated, service_role;
  RAISE NOTICE 'admin_order_margins gated';
END
$wrap$;

NOTIFY pgrst, 'reload schema';
