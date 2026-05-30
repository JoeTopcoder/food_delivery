-- ─────────────────────────────────────────────────────────────────────────────
-- Admin wallet adjustments
-- Adds debt_balance to wallets and admin RPC functions for credit/debt.
-- Debt is NOT deducted immediately — it clears automatically the next time
-- the customer's wallet receives funds (deposit, cashback, refund, tip).
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. Add debt_balance column
ALTER TABLE wallets
  ADD COLUMN IF NOT EXISTS debt_balance DECIMAL(12,2) NOT NULL DEFAULT 0
    CHECK (debt_balance >= 0);

-- 2. wallet_adjustments audit table
CREATE TABLE IF NOT EXISTS wallet_adjustments (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  admin_id     UUID NOT NULL REFERENCES auth.users(id),
  amount       DECIMAL(12,2) NOT NULL,   -- positive = credit, negative = debt added
  type         TEXT NOT NULL CHECK (type IN ('credit', 'debt')),
  description  TEXT NOT NULL,
  applied      BOOLEAN NOT NULL DEFAULT false,   -- true once debt is cleared
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE wallet_adjustments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admins_all_adjustments" ON wallet_adjustments
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "users_read_own_adjustments" ON wallet_adjustments
  FOR SELECT USING (user_id = auth.uid());

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. admin_wallet_adjust — add a credit or debt to a customer wallet
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION admin_wallet_adjust(
  p_user_id    UUID,
  p_amount     DECIMAL,   -- positive = credit, negative = debt
  p_description TEXT,
  p_admin_id   UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_type TEXT;
  v_abs  DECIMAL;
BEGIN
  -- Verify caller is admin
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_admin_id AND role = 'admin') THEN
    RAISE EXCEPTION 'Unauthorized: caller is not an admin';
  END IF;

  v_abs  := ABS(p_amount);
  v_type := CASE WHEN p_amount >= 0 THEN 'credit' ELSE 'debt' END;

  IF v_type = 'credit' THEN
    -- Credit: add directly to balance
    UPDATE wallets
    SET balance    = balance + v_abs,
        updated_at = NOW()
    WHERE user_id = p_user_id;

    INSERT INTO wallet_transactions (user_id, amount, type, status, description)
    VALUES (p_user_id, v_abs, 'admin_credit', 'completed', p_description);

    INSERT INTO wallet_adjustments (user_id, admin_id, amount, type, description, applied)
    VALUES (p_user_id, p_admin_id, v_abs, 'credit', p_description, true);

  ELSE
    -- Debt: add to debt_balance, does NOT reduce balance immediately.
    -- Will auto-clear on next deposit/cashback/refund.
    UPDATE wallets
    SET debt_balance = debt_balance + v_abs,
        updated_at   = NOW()
    WHERE user_id = p_user_id;

    INSERT INTO wallet_adjustments (user_id, admin_id, amount, type, description, applied)
    VALUES (p_user_id, p_admin_id, -v_abs, 'debt', p_description, false);
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'type',    v_type,
    'amount',  v_abs
  );
END;
$$;

GRANT EXECUTE ON FUNCTION admin_wallet_adjust(UUID, DECIMAL, TEXT, UUID) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. apply_wallet_debt — internal helper called whenever money enters the wallet
-- Clears outstanding debt from incoming funds before crediting the remainder.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION apply_wallet_debt(
  p_user_id      UUID,
  p_incoming_amt DECIMAL
)
RETURNS DECIMAL   -- returns amount remaining after debt deduction
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_debt      DECIMAL;
  v_cleared   DECIMAL;
  v_remaining DECIMAL;
BEGIN
  SELECT COALESCE(debt_balance, 0) INTO v_debt
  FROM wallets WHERE user_id = p_user_id FOR UPDATE;

  IF v_debt <= 0 THEN
    RETURN p_incoming_amt;   -- no debt, nothing to clear
  END IF;

  v_cleared   := LEAST(v_debt, p_incoming_amt);
  v_remaining := p_incoming_amt - v_cleared;

  -- Reduce the debt
  UPDATE wallets
  SET debt_balance = GREATEST(0, debt_balance - v_cleared),
      updated_at   = NOW()
  WHERE user_id = p_user_id;

  -- Record the debt-clearance as a transaction
  INSERT INTO wallet_transactions (user_id, amount, type, status, description)
  VALUES (p_user_id, -v_cleared, 'debt_clearance', 'completed',
          'Outstanding balance cleared from incoming funds');

  -- Mark adjustments applied (oldest first)
  UPDATE wallet_adjustments
  SET applied = true
  WHERE user_id = p_user_id
    AND type    = 'debt'
    AND applied = false;

  RETURN v_remaining;
END;
$$;

GRANT EXECUTE ON FUNCTION apply_wallet_debt(UUID, DECIMAL) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Update wallet_deposit to auto-clear debt before crediting balance
-- ─────────────────────────────────────────────────────────────────────────────

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
  -- Clear any outstanding debt first, then credit the remainder
  v_net := apply_wallet_debt(p_user_id, p_amount);

  UPDATE wallets
  SET balance    = balance + v_net,
      updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions (user_id, amount, type, status, description, payment_method)
  VALUES (p_user_id, p_amount, 'deposit', 'completed',
          'Wallet top-up via ' || p_method, p_method);

  RETURN (SELECT jsonb_build_object(
    'balance',          balance,
    'cashback_balance', cashback_balance
  ) FROM wallets WHERE user_id = p_user_id);
END;
$$;

GRANT EXECUTE ON FUNCTION wallet_deposit(UUID, DECIMAL, TEXT) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. Indexes
-- ─────────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_wallet_adjustments_user
  ON wallet_adjustments (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_wallet_adjustments_admin
  ON wallet_adjustments (admin_id, created_at DESC);
