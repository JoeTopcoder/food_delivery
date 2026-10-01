-- ============================================================================
-- Fix: a held (never-placed) sponsorship reservation locked the employee out of
-- re-selecting sponsorship for up to 15 min (abandoned checkout / lost UI state).
--
--  * Eligibility is now based on a successfully PLACED order only — a held
--    'reserved' row no longer hides the company selector.
--  * Reserving releases the employee's own stale 'reserved' holds for the day
--    first (a hold that never became an order is replaceable), so a retry always
--    succeeds. A 'placed' order still blocks (true once-per-day).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.company_eligible_for_checkout()
  RETURNS TABLE (company_id uuid, name text, delivery_address text,
                 latitude double precision, longitude double precision, radius_km smallint)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT c.id, c.name, c.delivery_address, c.latitude, c.longitude, c.radius_km
  FROM public.companies c
  JOIN public.company_members m ON m.company_id = c.id
  WHERE m.user_id = auth.uid() AND m.status = 'approved' AND c.is_active
    AND NOT EXISTS (
      SELECT 1 FROM public.company_sponsorship_usage u
      WHERE u.user_id = auth.uid() AND u.usage_date = public.jamaica_today()
        AND u.status = 'placed'          -- only a completed order consumes the day
    );
$$;

CREATE OR REPLACE FUNCTION public.company_reserve_sponsorship(
  p_company_id uuid, p_restaurant_id uuid, p_hold_minutes int DEFAULT 15)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); c public.companies; chk jsonb;
        v_id uuid; v_today date := public.jamaica_today();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
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

  -- Release this user's own held (not-yet-placed) reservations for today — a
  -- hold that never became an order is replaceable, so a retry never deadlocks.
  UPDATE public.company_sponsorship_usage SET status='released'
   WHERE user_id=v_uid AND usage_date=v_today AND status='reserved';

  BEGIN
    INSERT INTO public.company_sponsorship_usage (user_id, company_id, usage_date, status, expires_at)
    VALUES (v_uid, p_company_id, v_today, 'reserved', now() + make_interval(mins => p_hold_minutes))
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    -- Only a 'placed' row remains in the partial unique index now.
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

-- Clear the current stuck hold so the employee can proceed immediately
-- (scoped to the affected test user).
UPDATE public.company_sponsorship_usage SET status='released'
 WHERE status='reserved' AND usage_date = public.jamaica_today()
   AND user_id = '7aa9d538-6c5d-483a-b313-fc99d6f2bb0b';
