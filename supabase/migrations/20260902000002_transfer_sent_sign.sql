-- Migration: store outgoing transfers as a negative amount
--
-- wallet_transactions stores debits negative and credits positive — 'payment'
-- rows are -11.43, -12.46 etc, while deposit/cashback/refund/admin_credit are
-- positive. wallet_transfer() broke that convention by writing BOTH ledger rows
-- with the same positive p_amount.
--
-- The wallet history decides direction purely from the sign
-- (`final isCredit = tx.amount > 0` in wallet_screen.dart), so an outgoing
-- transfer rendered as a green +$20.00 credit on the sender's own history —
-- money leaving the account displayed as money arriving.
--
-- Only the sender's row changes. 'transfer_received' is already correct as a
-- positive credit, and wallets.balance is authoritative and untouched by this
-- (nothing derives a balance by summing wallet_transactions), so this is purely
-- a ledger-presentation correction.

CREATE OR REPLACE FUNCTION public.wallet_transfer(
  p_sender_id           UUID,
  p_recipient_wallet_id TEXT,
  p_amount              DECIMAL,
  p_note                TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller         UUID := auth.uid();
  v_sender_id      UUID;
  v_recipient_id   UUID;
  v_sender_name    TEXT;
  v_recipient_name TEXT;
  v_sender_bal     DECIMAL;
BEGIN
  -- A JWT-bearing caller may only ever move money out of their OWN wallet,
  -- whatever p_sender_id claims. auth.uid() is NULL for service-role/direct-SQL
  -- callers, which are already trusted; anon has no EXECUTE grant.
  IF v_caller IS NOT NULL AND v_caller IS DISTINCT FROM p_sender_id THEN
    RAISE EXCEPTION 'You can only transfer from your own wallet';
  END IF;
  v_sender_id := COALESCE(v_caller, p_sender_id);

  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  IF p_amount <> ROUND(p_amount, 2) THEN
    RAISE EXCEPTION 'Amount cannot have more than 2 decimal places';
  END IF;

  SELECT id, name INTO v_recipient_id, v_recipient_name
  FROM   public.users
  WHERE  UPPER(COALESCE(referral_code, '')) = UPPER(TRIM(p_recipient_wallet_id))
      OR UPPER(LEFT(REPLACE(id::text, '-', ''), 6)) = UPPER(TRIM(p_recipient_wallet_id))
  LIMIT  1;

  IF v_recipient_id IS NULL THEN
    RAISE EXCEPTION 'Wallet ID not found';
  END IF;

  IF v_recipient_id = v_sender_id THEN
    RAISE EXCEPTION 'Cannot transfer to your own wallet';
  END IF;

  SELECT balance INTO v_sender_bal
  FROM   public.wallets
  WHERE  user_id = v_sender_id
  FOR UPDATE;

  IF v_sender_bal IS NULL OR v_sender_bal < p_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  SELECT name INTO v_sender_name FROM public.users WHERE id = v_sender_id;

  UPDATE public.wallets
  SET    balance    = balance - p_amount,
         updated_at = now()
  WHERE  user_id = v_sender_id;

  INSERT INTO public.wallets (user_id, balance)
  VALUES (v_recipient_id, p_amount)
  ON CONFLICT (user_id) DO UPDATE
    SET balance    = public.wallets.balance + p_amount,
        updated_at = now();

  INSERT INTO public.wallet_transactions
    (user_id, amount, type, payment_method, status, description)
  VALUES
    -- Negative: money left this wallet. Matches how 'payment' is stored and is
    -- what the history uses to render this as a debit rather than a credit.
    (v_sender_id,    -p_amount, 'transfer_sent',     'wallet', 'completed',
     COALESCE(NULLIF(TRIM(p_note), ''),
              'Sent to ' || COALESCE(v_recipient_name, TRIM(p_recipient_wallet_id)))),
    (v_recipient_id,  p_amount, 'transfer_received', 'wallet', 'completed',
     'Received from ' || COALESCE(v_sender_name, 'a 7Dash user')
       || COALESCE(' — ' || NULLIF(TRIM(p_note), ''), ''));

  RETURN (
    SELECT jsonb_build_object('balance', balance, 'cashback_balance', cashback_balance)
    FROM   public.wallets
    WHERE  user_id = v_sender_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.wallet_transfer TO authenticated;
REVOKE EXECUTE ON FUNCTION public.wallet_transfer FROM anon;

-- Correct the rows already written with the wrong sign. Guarded so it can only
-- ever flip a positive 'transfer_sent' row, making this safe to re-run.
UPDATE public.wallet_transactions
SET    amount = -amount
WHERE  type = 'transfer_sent' AND amount > 0;

NOTIFY pgrst, 'reload schema';
