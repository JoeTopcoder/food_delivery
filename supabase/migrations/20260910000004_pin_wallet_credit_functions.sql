-- SECURITY: bound the wallet credit primitives for logged-in callers.
--
-- After removing anon access, wallet_credit and wallet_deposit were still
-- callable by any authenticated user with a caller-supplied p_user_id and
-- amount and no identity check, so a logged-in attacker could credit ANY
-- wallet ANY amount. The refund and top-up flows only ever credit the caller's
-- own wallet, and the three edge functions that credit other users run as the
-- service role (NULL auth.uid()), so both can be constrained without touching
-- any legitimate path:
--
--   * a JWT caller may credit only their own wallet (p_user_id = auth.uid())
--   * a JWT caller is capped per transaction (wallet_max_client_txn, config)
--   * a backend caller (service_role / direct SQL, NULL auth.uid()) is trusted
--     to name any user and amount, exactly as before
--
-- This bounds a compromised client to inflating its OWN wallet up to the cap,
-- which is traceable to that account. It does NOT by itself make top-up sound:
-- wallet_deposit still credits without confirming a real payment, so the true
-- fix is to credit top-ups from a payment-provider webhook (service role)
-- after settlement. That is flagged separately; this is the floor.

CREATE OR REPLACE FUNCTION public.wallet_client_txn_cap()
RETURNS numeric LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT NULLIF(value,'')::numeric FROM public.app_config
      WHERE key = 'wallet_max_client_txn'),
    50000);
$$;

-- ── wallet_credit: own-wallet + cap for JWT callers ─────────────────────────
CREATE OR REPLACE FUNCTION public.wallet_credit(
  p_user_id uuid, p_amount numeric, p_description text DEFAULT 'Wallet refund'::text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  IF auth.uid() IS NOT NULL THEN
    IF p_user_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'You can only credit your own wallet'
        USING errcode = 'insufficient_privilege';
    END IF;
    IF p_amount > public.wallet_client_txn_cap() THEN
      RAISE EXCEPTION 'Amount exceeds the per-transaction limit';
    END IF;
  END IF;

  INSERT INTO wallets (user_id, balance, cashback_balance)
  VALUES (p_user_id, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  UPDATE wallets
  SET balance = COALESCE(balance, 0) + p_amount, updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions (user_id, amount, type, payment_method, status, description)
  VALUES (p_user_id, p_amount, 'refund', 'wallet', 'completed', p_description);
END;
$function$;

-- ── wallet_deposit: own-wallet + cap for JWT callers ────────────────────────
CREATE OR REPLACE FUNCTION public.wallet_deposit(
  p_user_id uuid, p_amount numeric, p_method text DEFAULT 'card'::text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $function$
DECLARE
  v_net DECIMAL;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  IF auth.uid() IS NOT NULL THEN
    IF p_user_id IS DISTINCT FROM auth.uid() THEN
      RAISE EXCEPTION 'You can only top up your own wallet'
        USING errcode = 'insufficient_privilege';
    END IF;
    IF p_amount > public.wallet_client_txn_cap() THEN
      RAISE EXCEPTION 'Amount exceeds the per-transaction limit';
    END IF;
  END IF;

  INSERT INTO wallets (user_id, balance, cashback_balance, debt_balance)
  VALUES (p_user_id, 0, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  v_net := apply_wallet_debt(p_user_id, p_amount);

  UPDATE wallets
  SET balance = balance + v_net, updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions
    (user_id, amount, type, status, description, payment_method)
  VALUES
    (p_user_id, p_amount, 'deposit', 'completed',
     'Wallet top-up via ' || p_method, p_method);

  RETURN (
    SELECT jsonb_build_object(
      'balance', balance, 'cashback_balance', cashback_balance,
      'debt_balance', debt_balance)
    FROM wallets WHERE user_id = p_user_id
  );
END;
$function$;

-- Recreated functions default to owner-only EXECUTE; restore the grants the
-- prior migration set (authenticated + service_role, never anon/PUBLIC).
REVOKE EXECUTE ON FUNCTION public.wallet_credit(uuid, numeric, text) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.wallet_deposit(uuid, numeric, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.wallet_credit(uuid, numeric, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.wallet_deposit(uuid, numeric, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
