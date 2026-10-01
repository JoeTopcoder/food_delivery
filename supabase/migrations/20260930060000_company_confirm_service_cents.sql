-- Add an explicit service-fee argument to company_confirm_sponsorship.
-- The service fee is computed in the checkout UI (AppConstants.calculateServiceFee)
-- and folded into the employee's total; place-order does not store it as a
-- separate column. For sponsored orders the employee is NOT charged it, so
-- place-order passes the would-be service fee here to record the COMPANY charge.
DROP FUNCTION IF EXISTS public.company_confirm_sponsorship(uuid, uuid);

CREATE OR REPLACE FUNCTION public.company_confirm_sponsorship(
  p_reservation_id uuid, p_order_id uuid, p_service_cents int DEFAULT NULL)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE u public.company_sponsorship_usage; c public.companies; o public.orders;
        v_service_cents int; v_count int; v_tier int;
BEGIN
  SELECT * INTO u FROM public.company_sponsorship_usage WHERE id=p_reservation_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'Reservation not found'; END IF;
  IF u.status = 'placed' AND u.order_id = p_order_id THEN
    RETURN jsonb_build_object('ok',true,'already',true);
  END IF;
  IF u.status <> 'reserved' THEN RAISE EXCEPTION 'Reservation not active'; END IF;

  SELECT * INTO c FROM public.companies WHERE id=u.company_id;
  SELECT * INTO o FROM public.orders WHERE id=p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;

  v_service_cents := coalesce(p_service_cents, round(coalesce(o.platform_service_fee,0)::numeric*100)::int, 0);

  SELECT count(*) INTO v_count FROM public.company_sponsorship_usage
   WHERE company_id=u.company_id AND usage_date=u.usage_date AND status IN ('reserved','placed');
  v_tier := public.company_delivery_tier_cents(v_count);

  UPDATE public.company_sponsorship_usage
     SET status='placed', order_id=p_order_id, expires_at=NULL WHERE id=p_reservation_id;

  UPDATE public.orders SET
     is_company_sponsored = true,
     company_id = u.company_id,
     company_sponsorship_date = u.usage_date,
     company_delivery_cents = v_tier,
     company_service_cents  = v_service_cents,
     company_address_snapshot = jsonb_build_object('address',c.delivery_address,'lat',c.latitude,'lon',c.longitude),
     company_distance_km = public.geo_distance_km(
        (SELECT latitude FROM public.restaurants WHERE id=o.restaurant_id),
        (SELECT longitude FROM public.restaurants WHERE id=o.restaurant_id),
        c.latitude, c.longitude),
     company_radius_km = c.radius_km,
     company_charge_status = 'estimated'
   WHERE id = p_order_id;

  RETURN jsonb_build_object('ok',true,'delivery_cents',v_tier,'service_cents',v_service_cents);
END; $$;

REVOKE ALL ON FUNCTION public.company_confirm_sponsorship(uuid,uuid,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_confirm_sponsorship(uuid,uuid,int) TO service_role;

NOTIFY pgrst, 'reload schema';
