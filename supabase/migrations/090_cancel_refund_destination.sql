-- Migration 090: Allow customer to choose cancellation refund destination
-- card orders: original card or wallet
-- cash orders: no refund transfer

CREATE OR REPLACE FUNCTION public.cancel_order_with_penalty(
  p_order_id UUID,
  p_user_id UUID,
  p_refund_method TEXT DEFAULT 'original'
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_order orders;
  v_minutes_passed DOUBLE PRECISION;
  v_penalty DECIMAL := 0;
  v_refund DECIMAL := 0;
  v_result TEXT;
  v_refund_method TEXT := COALESCE(NULLIF(p_refund_method, ''), 'original');
BEGIN
  SELECT * INTO v_order
  FROM orders
  WHERE id = p_order_id AND user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.status NOT IN ('pending', 'confirmed', 'preparing') THEN
    RAISE EXCEPTION 'Cannot cancel order in status: %', v_order.status;
  END IF;

  IF v_refund_method NOT IN ('original', 'wallet') THEN
    v_refund_method := 'original';
  END IF;

  v_minutes_passed := EXTRACT(EPOCH FROM (now() - v_order.ordered_at)) / 60.0;

  IF v_minutes_passed < 5 THEN
    v_result := 'cancelled_free';
    v_penalty := 0;
  ELSIF v_order.status = 'preparing' THEN
    v_penalty := ROUND(v_order.total_amount * 0.15, 2);
    v_result := 'cancelled_with_fee';
  ELSE
    v_penalty := 1.00;
    v_result := 'cancelled_with_fee';
  END IF;

  UPDATE orders
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO wallets (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  IF v_order.payment_method = 'wallet' THEN
    v_refund := GREATEST(v_order.total_amount - v_penalty, 0);
    v_refund_method := 'wallet';

    IF v_refund > 0 THEN
      UPDATE wallets
      SET balance = balance + v_refund,
          updated_at = now()
      WHERE user_id = p_user_id;

      INSERT INTO wallet_transactions (
        user_id, amount, type, payment_method, status, order_id, description
      )
      VALUES (
        p_user_id,
        v_refund,
        'refund',
        'wallet',
        'completed',
        p_order_id,
        CASE WHEN v_penalty > 0
          THEN 'Refund for order #' || UPPER(LEFT(p_order_id::text, 8)) || ' (minus $' || v_penalty::text || ' fee)'
          ELSE 'Full refund for order #' || UPPER(LEFT(p_order_id::text, 8))
        END
      );
    END IF;

  ELSIF v_order.payment_method = 'card' THEN
    v_refund := GREATEST(v_order.total_amount - v_penalty, 0);

    IF v_refund_method = 'wallet' AND v_refund > 0 THEN
      UPDATE wallets
      SET balance = balance + v_refund,
          updated_at = now()
      WHERE user_id = p_user_id;

      INSERT INTO wallet_transactions (
        user_id, amount, type, payment_method, status, order_id, description
      )
      VALUES (
        p_user_id,
        v_refund,
        'refund',
        'wallet',
        'completed',
        p_order_id,
        CASE WHEN v_penalty > 0
          THEN 'Card order refund moved to wallet for order #' || UPPER(LEFT(p_order_id::text, 8)) || ' (minus $' || v_penalty::text || ' fee)'
          ELSE 'Card order refund moved to wallet for order #' || UPPER(LEFT(p_order_id::text, 8))
        END
      );

      UPDATE orders
      SET payment_status = 'refunded',
          updated_at = now()
      WHERE id = p_order_id;
    ELSE
      v_refund_method := 'original';
      -- Stripe refund is triggered by app flow when refund_method='original'.
    END IF;

  ELSIF v_order.payment_method = 'cash' THEN
    -- Cash orders have no payment refund transfer.
    v_refund := 0;
    v_refund_method := 'none';
  ELSE
    v_refund := 0;
    v_refund_method := 'none';
  END IF;

  -- Compensation to assigned driver when a cancellation fee applies.
  IF v_penalty > 0 AND v_order.driver_id IS NOT NULL THEN
    INSERT INTO wallets (user_id, balance)
    VALUES (v_order.driver_id, v_penalty)
    ON CONFLICT (user_id) DO UPDATE SET
      balance = wallets.balance + v_penalty,
      updated_at = now();

    INSERT INTO wallet_transactions (
      user_id, amount, type, payment_method, status, order_id, description
    )
    VALUES (
      v_order.driver_id,
      v_penalty,
      'tip_received',
      'system',
      'completed',
      p_order_id,
      'Cancellation compensation'
    );
  END IF;

  RETURN jsonb_build_object(
    'result', v_result,
    'penalty', v_penalty,
    'refund', v_refund,
    'refund_method', v_refund_method,
    'payment_method', v_order.payment_method,
    'total_amount', v_order.total_amount,
    'minutes_passed', ROUND(v_minutes_passed::numeric, 1)
  );
END;
$$;
