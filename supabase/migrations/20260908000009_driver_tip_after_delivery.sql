-- Migration: let a customer tip the driver AFTER delivery.
--
-- Tipping happens at checkout today — before anyone has done anything. Moving
-- it after delivery means the customer tips on service actually received, and
-- it raises driver earnings, which is the binding constraint on supply: there
-- are six drivers and two available.
--
-- The customer side uses wallet_deduct, which already locks the row FOR UPDATE,
-- spends cashback before balance, and refuses an overdraw.
--
-- The driver side does NOT use wallet_credit, which hardcodes type 'refund' —
-- a driver's history would read "Refund" for every tip they earned. The type
-- 'tip_received' already exists in wallet_transactions_type_check and has never
-- been used; this is what it was for. The credit is written here, mirroring
-- wallet_credit's locking, with the right word on it.

INSERT INTO public.app_config (key, value, value_type, description)
VALUES ('max_driver_tip', '5000', 'number',
        'Largest single tip a customer can add to one order (JMD)')
ON CONFLICT (key) DO UPDATE SET value_type = 'number',
                                description = EXCLUDED.description;

CREATE OR REPLACE FUNCTION public.add_driver_tip(
  p_order_id UUID,
  p_amount   NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_customer UUID := auth.uid();
  v_owner    UUID;
  -- orders.driver_id references drivers.id, which is NOT the driver's users.id
  -- — they differ for every driver on file. Crediting driver_id directly pays
  -- a wallet that does not exist.
  v_driver_row UUID;
  v_driver     UUID;
  v_status   TEXT;
  v_existing NUMERIC;
  v_max      NUMERIC;
  v_receipt  TEXT;
BEGIN
  IF v_customer IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Tip must be more than zero';
  END IF;

  SELECT o.user_id, o.driver_id, o.status, COALESCE(o.driver_tip, 0),
         COALESCE(o.receipt_number, left(o.id::text, 8))
    INTO v_owner, v_driver_row, v_status, v_existing, v_receipt
  FROM public.orders o WHERE o.id = p_order_id;

  SELECT d.user_id INTO v_driver FROM public.drivers d WHERE d.id = v_driver_row;

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;
  -- The order is taken from the id, but WHOSE order it is comes from the
  -- session. Otherwise any signed-in user could tip from someone else's wallet.
  IF v_owner <> v_customer THEN
    RAISE EXCEPTION 'That is not your order';
  END IF;
  IF v_status <> 'delivered' THEN
    RAISE EXCEPTION 'You can tip once the order has been delivered';
  END IF;
  IF v_driver_row IS NULL THEN
    RAISE EXCEPTION 'This order had no driver to tip';
  END IF;
  IF v_driver IS NULL THEN
    RAISE EXCEPTION 'That driver record is not linked to an account';
  END IF;

  v_max := COALESCE(
    (SELECT value FROM public.app_config WHERE key = 'max_driver_tip')::NUMERIC,
    5000);
  IF p_amount > v_max THEN
    RAISE EXCEPTION 'A single tip cannot be more than %', v_max;
  END IF;

  -- Customer pays first. If this raises — no wallet, not enough — nothing
  -- below runs and the driver is not credited money that was never taken.
  PERFORM public.wallet_deduct(
    v_customer, p_amount, 'Tip for order ' || v_receipt);

  -- Driver credit. Positive amount, per the ledger's sign convention:
  -- debits negative, credits positive.
  UPDATE public.wallets
     SET balance = COALESCE(balance, 0) + p_amount,
         updated_at = now()
   WHERE user_id = v_driver;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Driver has no wallet to receive the tip';
  END IF;

  INSERT INTO public.wallet_transactions
    (user_id, amount, type, payment_method, status, description)
  VALUES
    (v_driver, p_amount, 'tip_received', 'wallet', 'completed',
     'Tip from order ' || v_receipt);

  UPDATE public.orders
     SET driver_tip = v_existing + p_amount
   WHERE id = p_order_id;

  RETURN jsonb_build_object(
    'tipped',    TRUE,
    'amount',    p_amount,
    'total_tip', v_existing + p_amount
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_driver_tip TO authenticated;

NOTIFY pgrst, 'reload schema';
