-- Migration: fix wallet-to-wallet transfer
--
-- Three defects fixed, all of which made peer transfers impossible or unsafe:
--
-- 1. TYPE MISMATCH (the reason transfers always failed).
--    20260518000002_wallet_transfer.sql added 'transfer_sent'/'transfer_received'
--    to wallet_transactions_type_check and wrote a wallet_transfer() that inserts
--    those two types. A later migration rebuilt that constraint from an older
--    list, allowing 'transfer_in'/'transfer_out' instead — but nothing updated
--    the function. Every transfer therefore died on a 23514 check violation
--    before committing, which is why wallet_transactions contains zero rows of
--    any transfer type. The Flutter wallet screen renders 'transfer_sent' /
--    'transfer_received', so the constraint is widened to accept those (the
--    'transfer_in'/'transfer_out' spellings are kept so nothing else breaks).
--
-- 2. AUTHORIZATION HOLE (any user could drain any other user's wallet).
--    wallet_transfer() is SECURITY DEFINER, takes the sender as a parameter, and
--    is granted to `authenticated`. Nothing tied p_sender_id to the caller, so
--    any logged-in user could pass someone else's UUID and move their money out.
--    The sender is now pinned to auth.uid() for every JWT-bearing caller.
--
-- 3. DOUBLE-SPEND RACE.
--    The balance was read, checked, then decremented in separate statements with
--    no lock, so two concurrent transfers could both pass the check and overdraw.
--    The sender's wallet row is now locked FOR UPDATE and re-read inside the lock.

-- ── 1. Allow the transaction types the function and the app actually use ─────
ALTER TABLE public.wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;

ALTER TABLE public.wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check
  CHECK (type IN (
    'deposit','payment','cashback','refund','penalty','tip_received',
    'admin_credit','debt_clearance',
    -- legacy spellings, retained so existing rows/callers keep working
    'transfer_in','transfer_out',
    -- what wallet_transfer() writes and what the wallet screen renders
    'transfer_sent','transfer_received'
  ));

-- ── 2. Recreate the transfer function, secured and race-safe ────────────────
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
  -- Authorization. A JWT-bearing caller may only ever move money out of their
  -- OWN wallet, regardless of what p_sender_id claims. auth.uid() is NULL for
  -- service-role/direct-SQL callers (admin tooling, migrations), which are
  -- already trusted and may still act on a user's behalf; the anon role has no
  -- EXECUTE grant on this function at all.
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

  -- Reject sub-cent/!=2dp amounts up front rather than letting rounding drift
  -- between the two ledger rows.
  IF p_amount <> ROUND(p_amount, 2) THEN
    RAISE EXCEPTION 'Amount cannot have more than 2 decimal places';
  END IF;

  -- Resolve the recipient from the wallet display ID the app shows users:
  -- their referral_code, or the first 6 hex chars of their UUID as a fallback
  -- (referral_code is NULL for essentially every user today).
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

  -- Lock the sender's row, then re-read the balance inside the lock so two
  -- concurrent transfers can't both pass the sufficiency check.
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

  -- Ledger entries for both sides. The note, when given, is the customer's own
  -- text; keep it on the sender row and label the recipient row so the receiver
  -- always sees who paid them.
  INSERT INTO public.wallet_transactions
    (user_id, amount, type, payment_method, status, description)
  VALUES
    (v_sender_id,    p_amount, 'transfer_sent',     'wallet', 'completed',
     COALESCE(NULLIF(TRIM(p_note), ''),
              'Sent to ' || COALESCE(v_recipient_name, TRIM(p_recipient_wallet_id)))),
    (v_recipient_id, p_amount, 'transfer_received', 'wallet', 'completed',
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

NOTIFY pgrst, 'reload schema';
