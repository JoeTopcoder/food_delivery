-- Platform revenue over-counted delivery income on free-delivery orders. The
-- platform's delivery-fee share was computed on the GROSS delivery_fee, ignoring
-- that a delivery-fee coupon (e.g. FREEDELIVERY) waived what the customer paid.
-- Fix: base the share on the NET delivery fee actually collected (gross minus the
-- portion of the promo discount that applied to delivery).

CREATE OR REPLACE FUNCTION public.record_platform_revenue(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o                   orders%ROWTYPE;
  v_driver_pct        numeric;
  v_commission        numeric;
  v_delivery_discount numeric := 0;
  v_net_delivery      numeric;
  v_delivery_share    numeric;
  v_hbshare           numeric;
  v_sfee              numeric;
  v_total             numeric;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id;
  END IF;

  SELECT COALESCE(NULLIF(value,'')::numeric, 0.80) INTO v_driver_pct
    FROM app_config WHERE key = 'driver_pay_percent';
  v_driver_pct := COALESCE(v_driver_pct, 0.80);

  -- Portion of the promo discount that was applied to the delivery fee.
  IF o.promo_code IS NOT NULL AND o.promo_code <> '' THEN
    SELECT CASE WHEN applies_to = 'delivery_fee'
                THEN LEAST(COALESCE(o.discount,0), COALESCE(o.delivery_fee,0))
                ELSE 0 END
      INTO v_delivery_discount
      FROM promo_codes WHERE code = o.promo_code LIMIT 1;
    v_delivery_discount := COALESCE(v_delivery_discount, 0);
  END IF;

  v_net_delivery   := GREATEST(COALESCE(o.delivery_fee,0) - v_delivery_discount, 0);

  v_commission     := COALESCE(o.commission_amount,
                        COALESCE(o.subtotal,0) * COALESCE(o.commission_rate,0))::numeric;
  v_delivery_share := (v_net_delivery * (1 - v_driver_pct))::numeric;
  v_hbshare        := COALESCE(o.hotbite_savings_share,0)::numeric;
  v_sfee           := COALESCE(o.platform_service_fee,0)::numeric;
  v_total          := ROUND(v_commission + v_delivery_share + v_hbshare + v_sfee, 2);

  INSERT INTO public.platform_revenue_ledger (
    order_id, restaurant_id, restaurant_commission,
    delivery_fee_platform_share, hotbite_savings_share, service_fee, total)
  VALUES (
    p_order_id, o.restaurant_id, ROUND(v_commission,2),
    ROUND(v_delivery_share,2), ROUND(v_hbshare,2), ROUND(v_sfee,2), v_total)
  ON CONFLICT (order_id) DO NOTHING;

  RETURN jsonb_build_object('order_id', p_order_id, 'total', v_total,
                            'hotbite_savings_share', ROUND(v_hbshare,2));
END;
$function$;

-- Backfill existing ledger rows for orders whose delivery fee was waived by a
-- delivery-fee promo: recompute the platform delivery share on net delivery.
WITH dp AS (
  SELECT l.order_id,
         GREATEST(COALESCE(o.delivery_fee,0)
           - LEAST(COALESCE(o.discount,0), COALESCE(o.delivery_fee,0)), 0)::numeric AS net_delivery
  FROM platform_revenue_ledger l
  JOIN orders o ON o.id = l.order_id
  JOIN promo_codes p ON p.code = o.promo_code AND p.applies_to = 'delivery_fee'
),
cfg AS (SELECT COALESCE(NULLIF(value,'')::numeric,0.80) pct FROM app_config WHERE key='driver_pay_percent')
UPDATE platform_revenue_ledger l
   SET delivery_fee_platform_share = ROUND(dp.net_delivery * (1 - (SELECT pct FROM cfg)), 2),
       total = ROUND(l.restaurant_commission
               + dp.net_delivery * (1 - (SELECT pct FROM cfg))
               + l.hotbite_savings_share + l.service_fee, 2)
  FROM dp
 WHERE l.order_id = dp.order_id;

NOTIFY pgrst, 'reload schema';
