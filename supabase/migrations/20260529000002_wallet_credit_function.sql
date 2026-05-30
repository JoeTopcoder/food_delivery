-- wallet_credit: add funds back to a user's wallet (refunds, compensation, etc.)
-- Mirrors wallet_deduct but in reverse — credits the main balance.

CREATE OR REPLACE FUNCTION public.wallet_credit(
  p_user_id     UUID,
  p_amount      DECIMAL,
  p_description TEXT DEFAULT 'Wallet refund'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  -- Ensure a wallet row exists
  INSERT INTO wallets (user_id, balance, cashback_balance)
  VALUES (p_user_id, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE wallets
  SET
    balance    = COALESCE(balance, 0) + p_amount,
    updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, description)
  VALUES (p_user_id, p_amount, 'refund', 'wallet', 'completed', p_description);
END;
$$;

GRANT EXECUTE ON FUNCTION public.wallet_credit(UUID, DECIMAL, TEXT) TO authenticated, service_role;
