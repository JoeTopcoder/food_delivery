-- Migration: close the two holes the first attempt left open.
--
-- 1. ANONYMOUS callers still got through. require_admin fell back to
--    p_fallback whenever auth.uid() was NULL — and it is NULL for anon exactly
--    as it is for direct SQL. Passing a known admin's UUID from the public anon
--    key therefore still worked: the test credited a wallet 999,999.
--
-- 2. Revoking anon does nothing to an AUTHENTICATED non-admin. The read RPCs
--    had no gate in their bodies, so any signed-in customer could read
--    platform-wide financials.
--
-- The gate uses the is_admin() helper that already exists in this database and
-- is already used by admin_verify_driver and admin_review_driver_application —
-- it is SECURITY DEFINER and keyed to auth.uid(), which is what was wanted all
-- along. No second helper is introduced for it.

-- require_admin stays only for admin_wallet_adjust, which takes an admin id as
-- a parameter and must still work from service_role and psql.
CREATE OR REPLACE FUNCTION public.require_admin(p_fallback UUID DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role   TEXT := COALESCE(auth.role(), '');
  v_caller UUID := auth.uid();
BEGIN
  -- An anon JWT is a request from the public internet carrying the key that
  -- ships inside the app. It never gets the trusted fallback.
  IF v_role = 'anon' THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- No JWT at all means service_role or direct SQL, both already trusted; only
  -- then is the caller-supplied id consulted.
  IF v_caller IS NULL AND v_role IN ('', 'service_role') THEN
    v_caller := p_fallback;
  END IF;

  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = v_caller AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  RETURN v_caller;
END;
$$;

GRANT EXECUTE ON FUNCTION public.require_admin TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.require_admin FROM anon;

-- ── Gate the ungated plpgsql RPCs in their own bodies ──────────────────────
-- Rewritten from each function's CURRENT definition, because definitions in
-- this repo drift from what is deployed. The check is inserted after the body's
-- opening BEGIN using plain string positions — a regexp_replace backreference
-- ate the $function$ delimiter on the first attempt and produced a function
-- whose body began with a control character.
DO $gate$
DECLARE
  r     RECORD;
  v_def TEXT;
  v_pos INT;
  v_new TEXT;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    JOIN pg_language l ON l.oid = p.prolang
    WHERE n.nspname = 'public'
      AND l.lanname = 'plpgsql'
      AND p.prosrc NOT ILIKE '%is_admin%'
      AND p.proname IN (
        'admin_survival_metrics','admin_toggle_user_status',
        'get_analytics_summary','get_platform_commission_summary',
        'get_top_restaurants'
      )
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_pos := position(E'\nBEGIN' IN v_def);
    IF v_pos = 0 THEN
      RAISE NOTICE 'SKIPPED % — no BEGIN found, needs manual review', r.proname;
      CONTINUE;
    END IF;
    v_new := left(v_def, v_pos + 5)
          || E'\n  IF NOT public.is_admin() THEN'
          || E'\n    RAISE EXCEPTION ''Forbidden: admin access required'';'
          || E'\n  END IF;'
          || substr(v_def, v_pos + 6);
    EXECUTE v_new;
    RAISE NOTICE 'gated %', r.proname;
  END LOOP;
END
$gate$;

NOTIFY pgrst, 'reload schema';
