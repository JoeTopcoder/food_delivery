-- Generic wallet deduction for non-order payments (rides, car service bookings).
-- Mirrors wallet_pay() but uses a free-text reference instead of a UUID order_id.

CREATE OR REPLACE FUNCTION public.wallet_deduct(
  p_user_id     UUID,
  p_amount      DECIMAL,
  p_description TEXT DEFAULT 'Wallet payment'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_wallet       RECORD;
  v_cashback     DECIMAL;
  v_from_cashback DECIMAL := 0;
  v_from_balance  DECIMAL := 0;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  SELECT * INTO v_wallet FROM wallets WHERE user_id = p_user_id FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Wallet not found for user';
  END IF;

  v_cashback := COALESCE(v_wallet.cashback_balance, 0);

  IF v_cashback >= p_amount THEN
    v_from_cashback := p_amount;
  ELSE
    v_from_cashback := v_cashback;
    v_from_balance  := p_amount - v_cashback;
  END IF;

  IF v_from_balance > COALESCE(v_wallet.balance, 0) THEN
    RAISE EXCEPTION 'Insufficient wallet balance';
  END IF;

  UPDATE wallets
  SET
    balance          = COALESCE(balance, 0)          - v_from_balance,
    cashback_balance = COALESCE(cashback_balance, 0) - v_from_cashback,
    updated_at       = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, description)
  VALUES (p_user_id, -p_amount, 'payment', 'wallet', 'completed', p_description);
END;
$$;

GRANT EXECUTE ON FUNCTION public.wallet_deduct(UUID, DECIMAL, TEXT) TO authenticated, service_role;
