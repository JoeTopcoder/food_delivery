-- Fix debt clearance at checkout.
--
-- Problem: checkout_settle_debt tried to pull the debt from wallet.balance,
-- which is wrong in both cases:
--   • Card payments  — Stripe charged the extra amount; wallet balance is untouched,
--                      so LEAST(debt, balance) = 0 and nothing is cleared.
--   • Wallet payments via edge function (food/grocery) — edge function already
--                      deducted the ORDER total only; outstandingDebt was not
--                      included, so debt_balance is never reduced.
--
-- Fix: Replace checkout_settle_debt with checkout_clear_debt_direct, which simply
-- reduces debt_balance by the exact amount that was charged, with no balance touch.
-- Callers are responsible for deducting outstandingDebt from the wallet balance
-- beforehand when the payment method is wallet (food/grocery via edge function).

CREATE OR REPLACE FUNCTION checkout_clear_debt_direct(
  p_user_id   UUID,
  p_amount    DECIMAL,        -- the outstanding debt amount that was charged
  p_reference TEXT DEFAULT 'checkout'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_debt   DECIMAL;
  v_clear  DECIMAL;
BEGIN
  IF p_amount <= 0 THEN RETURN; END IF;

  SELECT COALESCE(debt_balance, 0) INTO v_debt
  FROM wallets
  WHERE user_id = p_user_id
  FOR UPDATE;

  IF v_debt IS NULL OR v_debt <= 0 THEN RETURN; END IF;

  -- Clear exactly what was charged (never go below 0)
  v_clear := LEAST(p_amount, v_debt);

  UPDATE wallets
  SET debt_balance = GREATEST(0, debt_balance - v_clear),
      updated_at   = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions
    (user_id, amount, type, status, description)
  VALUES
    (p_user_id, -v_clear, 'debt_clearance', 'completed',
     'Outstanding balance cleared at checkout (' || p_reference || ')');

  -- Mark pending debt adjustments as applied
  UPDATE wallet_adjustments
  SET applied = true
  WHERE user_id = p_user_id
    AND type    = 'debt'
    AND applied = false;
END;
$$;

GRANT EXECUTE ON FUNCTION checkout_clear_debt_direct(UUID, DECIMAL, TEXT)
  TO authenticated;
