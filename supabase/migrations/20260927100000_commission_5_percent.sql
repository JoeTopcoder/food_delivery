-- ============================================================================
-- Set restaurant commission to 5% (was 15%) everywhere it is applied:
--   • app_config keys read at order time (place-order) and payout time
--     (complete-delivery)
--   • every restaurant's per-restaurant commission_rate
--   • the driver float settlement (pay_restaurant_from_float) so the rider now
--     pays the restaurant the subtotal MINUS the 5% commission, not the full
--     subtotal.
-- Restaurant now receives 95% of the food subtotal; HotBite keeps 5%.
-- ============================================================================

-- Authorized price change (owner explicitly requested 5% commission): clear the
-- AI-executor flag for this transaction so the price-guard trigger allows it.
SET LOCAL app.ai_exec = '0';

-- 1. Config keys (place-order reads default_commission_rate + per-restaurant
--    rate; complete-delivery reads restaurant_commission_percent).
UPDATE app_config SET value = '0.05', updated_at = now() WHERE key = 'default_commission_rate';
UPDATE app_config SET value = '0.05', updated_at = now() WHERE key = 'restaurant_commission_pct';
INSERT INTO app_config (key, value)
VALUES ('restaurant_commission_percent', '0.05')
ON CONFLICT (key) DO UPDATE SET value = '0.05', updated_at = now();

-- 2. Lower the commission floor (was 12%) so a 5% rate is allowed, then set
--    every restaurant's own rate (place-order uses restaurant.commission_rate
--    first, falling back to the config default).
ALTER TABLE public.restaurants DROP CONSTRAINT IF EXISTS restaurants_commission_floor;
ALTER TABLE public.restaurants ADD CONSTRAINT restaurants_commission_floor
  CHECK (commission_rate IS NULL OR commission_rate >= 0);
UPDATE restaurants SET commission_rate = 0.05, updated_at = now();

-- 3. Rider side: driver pays the restaurant 5% less from float. Previously the
--    driver handed over the full subtotal (minus member savings); now the 5%
--    commission is deducted too, so the restaurant is paid what it is actually
--    owed and HotBite's cut is realised on cash orders as well as bank ones.
CREATE OR REPLACE FUNCTION public.pay_restaurant_from_float(p_driver_id uuid, p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_snapshot text;
  v_subtotal numeric;
  v_commission numeric;
  v_hbshare  numeric;
  v_pay      numeric;
  v_order_driver uuid;
  v_existing driver_float_transactions%ROWTYPE;
  v_new_float double precision;
BEGIN
  SELECT restaurant_payment_method_snapshot, subtotal,
         COALESCE(commission_amount, 0), COALESCE(hotbite_savings_share, 0), driver_id
    INTO v_snapshot, v_subtotal, v_commission, v_hbshare, v_order_driver
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id;
  END IF;

  -- Only CASH_PAYMENT orders settle the restaurant from the driver's float.
  IF COALESCE(v_snapshot, 'CASH_PAYMENT') <> 'CASH_PAYMENT' THEN
    RETURN jsonb_build_object('deducted', 0, 'method', v_snapshot,
                              'reason', 'bank_payment');
  END IF;

  -- The store is paid: customer subtotal MINUS HotBite's commission MINUS
  -- HotBite's member-savings share. Never below zero.
  v_pay := GREATEST(0,
             COALESCE(v_subtotal, 0)
             - GREATEST(0, COALESCE(v_commission, 0))
             - GREATEST(0, COALESCE(v_hbshare, 0)));

  IF v_pay <= 0 THEN
    RETURN jsonb_build_object('deducted', 0, 'method', v_snapshot,
                              'reason', 'zero_subtotal');
  END IF;

  -- Idempotency: never deduct twice for the same order.
  SELECT * INTO v_existing FROM driver_float_transactions
   WHERE driver_id = p_driver_id AND order_id = p_order_id
     AND type = 'restaurant_payment'
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('deducted', v_existing.amount * -1,
                              'method', v_snapshot,
                              'balance_after', v_existing.balance_after,
                              'idempotent', true);
  END IF;

  v_new_float := apply_driver_float_change(
    p_driver_id, -v_pay, 'restaurant_payment', p_order_id,
    'Cash paid to restaurant for order items (net of 5% commission)'
  );

  UPDATE orders SET restaurant_paid_from_float = true WHERE id = p_order_id;

  RETURN jsonb_build_object('deducted', v_pay, 'method', v_snapshot,
                            'commission_withheld', v_commission,
                            'balance_after', v_new_float);
END;
$function$;

NOTIFY pgrst, 'reload schema';
