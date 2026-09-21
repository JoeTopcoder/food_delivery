-- ═══════════════════════════════════════════════════════════════════════════
-- Restaurant payment method (CASH_PAYMENT / BANK_PAYMENT) + driver-float link.
--
-- Business rule:
--   CASH_PAYMENT  → driver pays the restaurant in cash; the items subtotal is
--                   debited from the driver's float; the restaurant is NOT paid
--                   again through the restaurant payout run.
--   BANK_PAYMENT  → driver pays nothing; float untouched; the restaurant is
--                   paid through the existing restaurant payout run.
--
-- Reuses the existing float system (drivers.cash_float,
-- apply_driver_float_change, driver_float_transactions). No second float system.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Per-restaurant payment method (admin-controlled). Default CASH_PAYMENT,
--    which preserves today's behaviour (driver fronts the food cost).
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS restaurant_payment_method text NOT NULL DEFAULT 'CASH_PAYMENT';

ALTER TABLE public.restaurants
  DROP CONSTRAINT IF EXISTS restaurants_payment_method_check;
ALTER TABLE public.restaurants
  ADD CONSTRAINT restaurants_payment_method_check
  CHECK (restaurant_payment_method IN ('CASH_PAYMENT','BANK_PAYMENT'));

-- 2. Immutable per-order snapshot of the method + payout eligibility + a flag
--    recording that the driver settled the restaurant from float.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS restaurant_payment_method_snapshot text;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS restaurant_payout_eligible boolean;
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS restaurant_paid_from_float boolean NOT NULL DEFAULT false;

ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS orders_rest_pay_method_snapshot_check;
ALTER TABLE public.orders
  ADD CONSTRAINT orders_rest_pay_method_snapshot_check
  CHECK (restaurant_payment_method_snapshot IS NULL
      OR restaurant_payment_method_snapshot IN ('CASH_PAYMENT','BANK_PAYMENT'));

-- 3. Snapshot the method onto the order at INSERT. Grocery (white-label
--    partner) stores are always BANK_PAYMENT — settled through payout, never
--    fronted by the driver.
CREATE OR REPLACE FUNCTION public.set_order_restaurant_payment_snapshot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_method text;
  v_store  text;
BEGIN
  IF NEW.restaurant_payment_method_snapshot IS NULL THEN
    SELECT r.restaurant_payment_method, r.store_type
      INTO v_method, v_store
    FROM public.restaurants r WHERE r.id = NEW.restaurant_id;

    IF COALESCE(v_store, 'food') = 'grocery' THEN
      NEW.restaurant_payment_method_snapshot := 'BANK_PAYMENT';
    ELSE
      NEW.restaurant_payment_method_snapshot := COALESCE(v_method, 'CASH_PAYMENT');
    END IF;
  END IF;

  NEW.restaurant_payout_eligible :=
    (NEW.restaurant_payment_method_snapshot = 'BANK_PAYMENT');
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_rest_pay_snapshot_ins ON public.orders;
CREATE TRIGGER trg_order_rest_pay_snapshot_ins
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.set_order_restaurant_payment_snapshot();

-- 4. The snapshot is historical and must never change once written (an admin
--    flipping the restaurant's method must not rewrite old orders).
CREATE OR REPLACE FUNCTION public.lock_order_restaurant_payment_snapshot()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF OLD.restaurant_payment_method_snapshot IS NOT NULL THEN
    NEW.restaurant_payment_method_snapshot := OLD.restaurant_payment_method_snapshot;
    NEW.restaurant_payout_eligible := OLD.restaurant_payout_eligible;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_rest_pay_snapshot_upd ON public.orders;
CREATE TRIGGER trg_order_rest_pay_snapshot_upd
  BEFORE UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.lock_order_restaurant_payment_snapshot();

-- 5. Backfill existing orders (historical = whatever their restaurant is now;
--    grocery → BANK, everything else → CASH by default).
UPDATE public.orders o
SET restaurant_payment_method_snapshot = CASE
      WHEN COALESCE(r.store_type,'food') = 'grocery' THEN 'BANK_PAYMENT'
      ELSE COALESCE(r.restaurant_payment_method,'CASH_PAYMENT')
    END
FROM public.restaurants r
WHERE o.restaurant_id = r.id
  AND o.restaurant_payment_method_snapshot IS NULL;

UPDATE public.orders
SET restaurant_payout_eligible = (restaurant_payment_method_snapshot = 'BANK_PAYMENT')
WHERE restaurant_payout_eligible IS NULL;

-- 6. Idempotent, atomic restaurant-payment-from-float settlement.
--    Deducts the items subtotal from the driver's float for CASH_PAYMENT orders
--    only, exactly once per (driver, order). BANK_PAYMENT → no-op ($0).
--    Negative float is allowed (existing rule: negative = platform owes driver).
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
  v_order_driver uuid;
  v_existing driver_float_transactions%ROWTYPE;
  v_new_float double precision;
BEGIN
  SELECT restaurant_payment_method_snapshot, subtotal, driver_id
    INTO v_snapshot, v_subtotal, v_order_driver
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id;
  END IF;

  -- Only CASH_PAYMENT orders settle the restaurant from the driver's float.
  IF COALESCE(v_snapshot, 'CASH_PAYMENT') <> 'CASH_PAYMENT' THEN
    RETURN jsonb_build_object('deducted', 0, 'method', v_snapshot,
                              'reason', 'bank_payment');
  END IF;

  IF COALESCE(v_subtotal, 0) <= 0 THEN
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
    p_driver_id, -v_subtotal, 'restaurant_payment', p_order_id,
    'Cash paid to restaurant for order items'
  );

  UPDATE orders SET restaurant_paid_from_float = true WHERE id = p_order_id;

  RETURN jsonb_build_object('deducted', v_subtotal, 'method', v_snapshot,
                            'balance_after', v_new_float);
END;
$$;

REVOKE ALL ON FUNCTION public.pay_restaurant_from_float(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.pay_restaurant_from_float(uuid, uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
