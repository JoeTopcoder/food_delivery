-- Fix admin_wallet_adjust:
--   1. Extend wallet_transactions.type CHECK to include admin_credit and debt_clearance
--   2. Rewrite admin_wallet_adjust to:
--      a) upsert the wallet row (handles new users who have never deposited)
--      b) for debt: deduct from available balance first, record only the
--         remainder as debt_balance (cleared on next top-up)

-- ── 1. Extend the type constraint ────────────────────────────────────────────

ALTER TABLE wallet_transactions
  DROP CONSTRAINT IF EXISTS wallet_transactions_type_check;

ALTER TABLE wallet_transactions
  ADD CONSTRAINT wallet_transactions_type_check
  CHECK (type IN (
    'deposit',
    'payment',
    'cashback',
    'refund',
    'penalty',
    'tip_received',
    'admin_credit',
    'debt_clearance',
    'transfer_in',
    'transfer_out'
  ));

-- ── 2. Rewrite admin_wallet_adjust ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_wallet_adjust(
  p_user_id     UUID,
  p_amount      DECIMAL,   -- positive = credit, negative = debt
  p_description TEXT,
  p_admin_id    UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type           TEXT;
  v_abs            DECIMAL;
  v_current_bal    DECIMAL;
  v_deduct_now     DECIMAL;  -- portion cleared from balance immediately
  v_remaining_debt DECIMAL;  -- portion that becomes pending debt
BEGIN
  -- Verify caller is admin
  IF NOT EXISTS (
    SELECT 1 FROM users WHERE id = p_admin_id AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Unauthorized: caller is not an admin';
  END IF;

  -- Verify target user exists
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  v_abs  := ABS(p_amount);
  v_type := CASE WHEN p_amount >= 0 THEN 'credit' ELSE 'debt' END;

  -- Ensure wallet row exists (new users who haven't deposited yet won't have one)
  INSERT INTO wallets (user_id, balance, cashback_balance, debt_balance)
  VALUES (p_user_id, 0, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  IF v_type = 'credit' THEN
    -- ── Credit: add directly to spendable balance ────────────────────────────
    UPDATE wallets
    SET balance    = balance + v_abs,
        updated_at = NOW()
    WHERE user_id = p_user_id;

    INSERT INTO wallet_transactions
      (user_id, amount, type, status, description)
    VALUES
      (p_user_id, v_abs, 'admin_credit', 'completed', p_description);

  ELSE
    -- ── Debt: deduct from available balance first; remainder → debt_balance ──
    --
    -- Lock the row so concurrent top-ups don't race with us.
    SELECT GREATEST(COALESCE(balance, 0), 0)
    INTO v_current_bal
    FROM wallets
    WHERE user_id = p_user_id
    FOR UPDATE;

    v_deduct_now     := LEAST(v_current_bal, v_abs);   -- what we take now
    v_remaining_debt := v_abs - v_deduct_now;           -- what becomes debt

    UPDATE wallets
    SET balance      = balance      - v_deduct_now,
        debt_balance = COALESCE(debt_balance, 0) + v_remaining_debt,
        updated_at   = NOW()
    WHERE user_id = p_user_id;

    -- Record the immediate deduction as a transaction (only if something was taken)
    IF v_deduct_now > 0 THEN
      INSERT INTO wallet_transactions
        (user_id, amount, type, status, description)
      VALUES
        (p_user_id, -v_deduct_now, 'debt_clearance', 'completed',
         p_description || ' (deducted from balance)');
    END IF;
  END IF;

  -- Always audit every adjustment
  INSERT INTO wallet_adjustments
    (user_id, admin_id, amount, type, description, applied)
  VALUES
    (p_user_id, p_admin_id,
     CASE WHEN v_type = 'credit' THEN v_abs ELSE -v_abs END,
     v_type,
     p_description,
     -- fully applied if credit, or if entire debt was covered by existing balance
     v_type = 'credit' OR (v_type = 'debt' AND v_remaining_debt = 0));

  RETURN jsonb_build_object(
    'success',        true,
    'type',           v_type,
    'amount',         v_abs,
    'deducted_now',   COALESCE(v_deduct_now, 0),
    'pending_debt',   COALESCE(v_remaining_debt, 0)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_wallet_adjust(UUID, DECIMAL, TEXT, UUID)
  TO authenticated;
