-- ─────────────────────────────────────────────────────────────────────────
-- Server-authoritative wallet top-ups.
--
-- Before: the client called wallet_deposit(p_user_id, p_amount) directly after
-- a client-side Stripe confirm. Nothing tied the credited amount to a REAL
-- Stripe charge, so a logged-in user could call the RPC straight from the API
-- and credit their wallet without paying.
--
-- After: wallet_deposit is REVOKED from authenticated/anon. Credits only happen
-- through wallet_credit_from_stripe(), which is granted to service_role and
-- called by the stripe/payment edge function AFTER it verifies the PaymentIntent
-- succeeded with Stripe. Crediting is idempotent on the PaymentIntent id, so a
-- replayed confirm can never double-credit.
-- ─────────────────────────────────────────────────────────────────────────

-- 1. Idempotency key: which Stripe PaymentIntent produced this ledger row.
ALTER TABLE public.wallet_transactions
  ADD COLUMN IF NOT EXISTS stripe_payment_intent_id text;

CREATE UNIQUE INDEX IF NOT EXISTS wallet_transactions_stripe_pi_uniq
  ON public.wallet_transactions (stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

-- 2. Server-authoritative credit. service_role only — the edge function has
--    already verified the PaymentIntent with Stripe before calling this.
CREATE OR REPLACE FUNCTION public.wallet_credit_from_stripe(
  p_user_id uuid,
  p_amount numeric,
  p_payment_intent_id text,
  p_method text DEFAULT 'card'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_net        DECIMAL;
  v_existing   uuid;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;
  IF p_payment_intent_id IS NULL OR length(trim(p_payment_intent_id)) = 0 THEN
    RAISE EXCEPTION 'A Stripe PaymentIntent id is required';
  END IF;

  -- Idempotency: if this PaymentIntent already credited, return current balance
  -- without crediting again.
  SELECT id INTO v_existing
  FROM wallet_transactions
  WHERE stripe_payment_intent_id = p_payment_intent_id
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN (
      SELECT jsonb_build_object(
        'balance', balance, 'cashback_balance', cashback_balance,
        'debt_balance', debt_balance, 'already_credited', true)
      FROM wallets WHERE user_id = p_user_id
    );
  END IF;

  INSERT INTO wallets (user_id, balance, cashback_balance, debt_balance)
  VALUES (p_user_id, 0, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  v_net := apply_wallet_debt(p_user_id, p_amount);

  UPDATE wallets
  SET balance = balance + v_net, updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions
    (user_id, amount, type, status, description, payment_method,
     stripe_payment_intent_id)
  VALUES
    (p_user_id, p_amount, 'deposit', 'completed',
     'Wallet top-up via ' || p_method, p_method, p_payment_intent_id);

  RETURN (
    SELECT jsonb_build_object(
      'balance', balance, 'cashback_balance', cashback_balance,
      'debt_balance', debt_balance, 'already_credited', false)
    FROM wallets WHERE user_id = p_user_id
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.wallet_credit_from_stripe(uuid, numeric, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.wallet_credit_from_stripe(uuid, numeric, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.wallet_credit_from_stripe(uuid, numeric, text, text) TO service_role;

-- 3. Lock down the old client-callable deposit. Clients can no longer credit
--    their own wallet directly; service_role (edge functions / admin SQL) keeps
--    access for legitimate server-side use.
REVOKE EXECUTE ON FUNCTION public.wallet_deposit(uuid, numeric, text) FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';
