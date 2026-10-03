-- Shared Member Savings — CASH_PAYMENT float settlement.
-- When a driver settles a CASH_PAYMENT restaurant from float, they must pay the
-- store only its agreed amount (store_member_price), NOT the customer-charged
-- member price. The customer paid subtotal = store_member_price + HotBite's
-- savings share (orders.hotbite_savings_share); netting the share out leaves
-- exactly the store payout, and the share stays with the platform (it reduces
-- the driver's float debit, mirroring the cash the driver collected COD).
-- Non-member orders have hotbite_savings_share = 0, so behaviour is unchanged.
CREATE OR REPLACE FUNCTION public.pay_restaurant_from_float(
  p_driver_id uuid,
  p_order_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_snapshot text;
  v_subtotal numeric;
  v_hbshare  numeric;
  v_pay      numeric;
  v_order_driver uuid;
  v_existing driver_float_transactions%ROWTYPE;
  v_new_float double precision;
BEGIN
  SELECT restaurant_payment_method_snapshot, subtotal,
         COALESCE(hotbite_savings_share, 0), driver_id
    INTO v_snapshot, v_subtotal, v_hbshare, v_order_driver
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id;
  END IF;

  -- Only CASH_PAYMENT orders settle the restaurant from the driver's float.
  IF COALESCE(v_snapshot, 'CASH_PAYMENT') <> 'CASH_PAYMENT' THEN
    RETURN jsonb_build_object('deducted', 0, 'method', v_snapshot,
                              'reason', 'bank_payment');
  END IF;

  -- The store is paid its agreed amount: customer subtotal minus HotBite's
  -- savings share. Never below zero.
  v_pay := GREATEST(0, COALESCE(v_subtotal, 0) - GREATEST(0, COALESCE(v_hbshare, 0)));

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

  -- Debit float (negative amount) via the existing audited RPC, then record the
  -- settlement on the order — both in this one transaction.
  v_new_float := apply_driver_float_change(
    p_driver_id, -v_pay, 'restaurant_payment', p_order_id,
    'Cash paid to restaurant for order items'
  );

  UPDATE orders SET restaurant_paid_from_float = true WHERE id = p_order_id;

  RETURN jsonb_build_object('deducted', v_pay, 'method', v_snapshot,
                            'balance_after', v_new_float);
END;
$$;

REVOKE ALL ON FUNCTION public.pay_restaurant_from_float(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pay_restaurant_from_float(uuid, uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
