-- ============================================================================
-- Admin on/off switch for Company-Sponsored Ordering (app_config flag).
-- Enforced server-side: when off, no company is eligible and no reservation can
-- be taken, so the checkout option disappears for everyone. Existing historical
-- orders/ledger are untouched.
-- ============================================================================

INSERT INTO public.app_config (key, value) VALUES ('company_sponsorship_enabled','true')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.company_sponsorship_enabled()
  RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT coalesce(
    (SELECT value IN ('true','1') FROM public.app_config WHERE key='company_sponsorship_enabled'),
    true);
$$;
GRANT EXECUTE ON FUNCTION public.company_sponsorship_enabled() TO authenticated, anon, service_role;

-- Eligibility respects the flag.
CREATE OR REPLACE FUNCTION public.company_eligible_for_checkout()
  RETURNS TABLE (company_id uuid, name text, delivery_address text,
                 latitude double precision, longitude double precision, radius_km smallint)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT c.id, c.name, c.delivery_address, c.latitude, c.longitude, c.radius_km
  FROM public.companies c
  JOIN public.company_members m ON m.company_id = c.id
  WHERE public.company_sponsorship_enabled()
    AND m.user_id = auth.uid() AND m.status = 'approved' AND c.is_active
    AND NOT EXISTS (
      SELECT 1 FROM public.company_sponsorship_usage u
      WHERE u.user_id = auth.uid() AND u.usage_date = public.jamaica_today()
        AND u.status = 'placed');
$$;

-- Reserve refuses when the feature is off.
CREATE OR REPLACE FUNCTION public.company_reserve_sponsorship(
  p_company_id uuid, p_restaurant_id uuid, p_hold_minutes int DEFAULT 15)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); c public.companies; chk jsonb;
        v_id uuid; v_today date := public.jamaica_today();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  IF NOT public.company_sponsorship_enabled() THEN
    RETURN jsonb_build_object('ok',false,'reason','feature_disabled'); END IF;
  SELECT * INTO c FROM public.companies WHERE id = p_company_id;
  IF c.id IS NULL OR NOT c.is_active THEN
    RETURN jsonb_build_object('ok',false,'reason','company_inactive'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.company_members m
                 WHERE m.company_id = p_company_id AND m.user_id = v_uid AND m.status='approved') THEN
    RETURN jsonb_build_object('ok',false,'reason','not_approved_member'); END IF;
  chk := public.company_check_restaurant(p_company_id, p_restaurant_id);
  IF (chk->>'eligible')::boolean IS NOT TRUE THEN
    RETURN jsonb_build_object('ok',false,'reason', chk->>'reason',
                              'distance_km', chk->'distance_km','radius_km', c.radius_km); END IF;

  UPDATE public.company_sponsorship_usage SET status='released'
   WHERE user_id=v_uid AND usage_date=v_today AND status='reserved';

  BEGIN
    INSERT INTO public.company_sponsorship_usage (user_id, company_id, usage_date, status, expires_at)
    VALUES (v_uid, p_company_id, v_today, 'reserved', now() + make_interval(mins => p_hold_minutes))
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok',false,'reason','already_used_today');
  END;

  RETURN jsonb_build_object(
    'ok', true, 'reservation_id', v_id,
    'company_id', p_company_id, 'company_name', c.name,
    'delivery_address', c.delivery_address,
    'latitude', c.latitude, 'longitude', c.longitude, 'radius_km', c.radius_km,
    'distance_km', chk->'distance_km',
    'estimated_delivery_cents', 35000, 'estimated_service_cents', 25000);
END; $$;

NOTIFY pgrst, 'reload schema';
