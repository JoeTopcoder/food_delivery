-- Debt clears on BOTH wallet top-up AND at checkout.
--
-- Changes:
--   1. Restore apply_wallet_debt call inside wallet_deposit so topping up
--      still auto-clears outstanding debt (unchanged from original behaviour).
--   2. New function checkout_settle_debt — also called after any successful
--      checkout payment to catch any debt that wasn't cleared by a prior top-up.

-- ── 1. wallet_deposit — restores debt-clearing on top-up ─────────────────────

CREATE OR REPLACE FUNCTION wallet_deposit(
  p_user_id UUID,
  p_amount  DECIMAL,
  p_method  TEXT DEFAULT 'card'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_net DECIMAL;
BEGIN
  -- Upsert wallet row so new users always have one
  INSERT INTO wallets (user_id, balance, cashback_balance, debt_balance)
  VALUES (p_user_id, 0, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  -- Clear any outstanding debt first, then credit the remainder to balance
  v_net := apply_wallet_debt(p_user_id, p_amount);

  UPDATE wallets
  SET balance    = balance + v_net,
      updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions
    (user_id, amount, type, status, description, payment_method)
  VALUES
    (p_user_id, p_amount, 'deposit', 'completed',
     'Wallet top-up via ' || p_method, p_method);

  RETURN (
    SELECT jsonb_build_object(
      'balance',          balance,
      'cashback_balance', cashback_balance,
      'debt_balance',     debt_balance
    )
    FROM wallets WHERE user_id = p_user_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION wallet_deposit(UUID, DECIMAL, TEXT) TO authenticated;

-- ── 2. checkout_settle_debt ───────────────────────────────────────────────────
-- Called fire-and-forget after any successful checkout payment.
-- Deducts outstanding debt from wallet balance (already funded by the payment)
-- and records the clearance.  Returns the settled amount (0 if no debt).

CREATE OR REPLACE FUNCTION checkout_settle_debt(
  p_user_id   UUID,
  p_reference TEXT DEFAULT 'checkout'  -- order_id, booking_id, or ride_id
)
RETURNS DECIMAL
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_debt    DECIMAL;
  v_balance DECIMAL;
  v_settle  DECIMAL;
BEGIN
  -- Lock the row
  SELECT COALESCE(debt_balance, 0), COALESCE(balance, 0)
  INTO v_debt, v_balance
  FROM wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_debt IS NULL OR v_debt <= 0 THEN
    RETURN 0;
  END IF;

  -- Settle as much as we can from the current balance
  v_settle := LEAST(v_debt, v_balance);

  IF v_settle <= 0 THEN
    RETURN 0;
  END IF;

  UPDATE wallets
  SET balance      = balance      - v_settle,
      debt_balance = debt_balance - v_settle,
      updated_at   = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions
    (user_id, amount, type, status, description)
  VALUES
    (p_user_id, -v_settle, 'debt_clearance', 'completed',
     'Outstanding balance cleared at checkout (' || p_reference || ')');

  -- Mark the oldest pending debt adjustments as applied
  UPDATE wallet_adjustments
  SET applied = true
  WHERE user_id = p_user_id
    AND type    = 'debt'
    AND applied = false;

  RETURN v_settle;
END;
$$;

-- Callable by the customer themselves (runs in their session after checkout)
GRANT EXECUTE ON FUNCTION checkout_settle_debt(UUID, TEXT) TO authenticated;
