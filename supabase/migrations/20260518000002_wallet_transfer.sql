-- Migration: wallet-to-wallet transfer

-- Allow new transaction types for peer transfers
ALTER TABLE public.wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;

ALTER TABLE public.wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check
  CHECK (type IN ('deposit','payment','cashback','refund','penalty',
                  'tip_received','transfer_sent','transfer_received'));

-- RPC: Transfer funds between wallets
-- Recipient is looked up by their referral_code (wallet display ID).
-- Fallback: first 6 uppercase chars of the UUID (without dashes).
CREATE OR REPLACE FUNCTION public.wallet_transfer(
  p_sender_id        UUID,
  p_recipient_wallet_id TEXT,
  p_amount           DECIMAL,
  p_note             TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_recipient_id   UUID;
  v_sender_name    TEXT;
  v_recipient_name TEXT;
  v_sender_bal     DECIMAL;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  -- Lookup recipient by referral_code OR first-6-chars of UUID
  SELECT id, name INTO v_recipient_id, v_recipient_name
  FROM   public.users
  WHERE  UPPER(COALESCE(referral_code, '')) = UPPER(p_recipient_wallet_id)
      OR UPPER(LEFT(REPLACE(id::text, '-', ''), 6)) = UPPER(p_recipient_wallet_id)
  LIMIT  1;

  IF v_recipient_id IS NULL THEN
    RAISE EXCEPTION 'Wallet ID not found';
  END IF;

  IF v_recipient_id = p_sender_id THEN
    RAISE EXCEPTION 'Cannot transfer to your own wallet';
  END IF;

  -- Check sender balance
  SELECT balance INTO v_sender_bal
  FROM   public.wallets
  WHERE  user_id = p_sender_id;

  IF v_sender_bal IS NULL OR v_sender_bal < p_amount THEN
    RAISE EXCEPTION 'Insufficient balance';
  END IF;

  SELECT name INTO v_sender_name FROM public.users WHERE id = p_sender_id;

  -- Deduct from sender
  UPDATE public.wallets
  SET    balance    = balance - p_amount,
         updated_at = now()
  WHERE  user_id = p_sender_id;

  -- Add to recipient (create wallet row if missing)
  INSERT INTO public.wallets (user_id, balance)
  VALUES (v_recipient_id, p_amount)
  ON CONFLICT (user_id) DO UPDATE
    SET balance    = public.wallets.balance + p_amount,
        updated_at = now();

  -- Ledger entries for both parties
  INSERT INTO public.wallet_transactions
    (user_id, amount, type, payment_method, status, description)
  VALUES
    (p_sender_id,    p_amount, 'transfer_sent',     'wallet', 'completed',
     COALESCE(p_note, 'Sent to ' || COALESCE(v_recipient_name, p_recipient_wallet_id))),
    (v_recipient_id, p_amount, 'transfer_received', 'wallet', 'completed',
     COALESCE(p_note, 'Received from ' || COALESCE(v_sender_name, 'User')));

  -- Return updated sender balance
  RETURN (
    SELECT jsonb_build_object('balance', balance, 'cashback_balance', cashback_balance)
    FROM   public.wallets
    WHERE  user_id = p_sender_id
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.wallet_transfer TO authenticated;
