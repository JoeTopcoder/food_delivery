-- Migration 077: Update cancellation policy
-- Free cancellation within 10 minutes, $1.50 flat fee after that
-- 15% fee if order is already preparing

CREATE OR REPLACE FUNCTION public.cancel_order_with_penalty(p_order_id UUID, p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order orders;
  v_minutes_passed DOUBLE PRECISION;
  v_penalty DECIMAL := 0;
  v_refund DECIMAL := 0;
  v_result TEXT;
BEGIN
  SELECT * INTO v_order FROM orders WHERE id = p_order_id AND user_id = p_user_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.status NOT IN ('pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Cannot cancel order in status: %', v_order.status;
  END IF;

  v_minutes_passed := EXTRACT(EPOCH FROM (now() - v_order.ordered_at)) / 60.0;

  IF v_minutes_passed < 10 THEN
    -- Free cancellation within 10 minutes
    v_result := 'cancelled_free';
    v_penalty := 0;
  ELSIF v_order.status = 'preparing' THEN
    -- If already preparing, charge 15% of total
    v_penalty := ROUND(v_order.total_amount * 0.15, 2);
    v_result := 'cancelled_with_fee';
  ELSE
    -- After 10 min but before preparing, flat $1.50 fee
    v_penalty := 1.50;
    v_result := 'cancelled_with_fee';
  END IF;

  -- Update order status
  UPDATE orders SET status = 'cancelled', updated_at = now() WHERE id = p_order_id;

  -- Ensure wallet exists
  INSERT INTO wallets (user_id) VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  -- ── Refund wallet-paid orders ─────────────────────────────
  IF v_order.payment_method = 'wallet' THEN
    v_refund := v_order.total_amount - v_penalty;

    IF v_refund > 0 THEN
      UPDATE wallets SET
        balance = balance + v_refund,
        updated_at = now()
      WHERE user_id = p_user_id;

      INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
      VALUES (p_user_id, v_refund, 'refund', 'wallet', 'completed', p_order_id,
        CASE WHEN v_penalty > 0
          THEN 'Refund for order #' || UPPER(LEFT(p_order_id::text, 8)) || ' (minus $' || v_penalty::text || ' fee)'
          ELSE 'Full refund for order #' || UPPER(LEFT(p_order_id::text, 8))
        END);
    END IF;

    IF v_penalty > 0 AND v_refund <= 0 THEN
      INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
      VALUES (p_user_id, -v_penalty, 'penalty', 'system', 'completed', p_order_id,
        'Cancellation fee for order #' || UPPER(LEFT(p_order_id::text, 8)));

      UPDATE wallets SET
        balance = GREATEST(balance - v_penalty, 0),
        updated_at = now()
      WHERE user_id = p_user_id;
    END IF;

  ELSE
    -- Non-wallet orders: deduct penalty from wallet if applicable
    IF v_penalty > 0 THEN
      INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
      VALUES (p_user_id, -v_penalty, 'penalty', 'system', 'completed', p_order_id,
        'Cancellation fee for order #' || UPPER(LEFT(p_order_id::text, 8)));

      UPDATE wallets SET
        balance = GREATEST(balance - v_penalty, 0),
        updated_at = now()
      WHERE user_id = p_user_id;
    END IF;
  END IF;

  -- If driver was assigned, credit them the penalty as compensation
  IF v_penalty > 0 AND v_order.driver_id IS NOT NULL THEN
    INSERT INTO wallets (user_id, balance) VALUES (v_order.driver_id, v_penalty)
    ON CONFLICT (user_id) DO UPDATE SET
      balance = wallets.balance + v_penalty,
      updated_at = now();

    INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
    VALUES (v_order.driver_id, v_penalty, 'tip_received', 'system', 'completed', p_order_id,
      'Cancellation compensation');
  END IF;

  RETURN jsonb_build_object(
    'result', v_result,
    'penalty', v_penalty,
    'refund', v_refund,
    'minutes_passed', ROUND(v_minutes_passed::numeric, 1)
  );
END;
$$;
