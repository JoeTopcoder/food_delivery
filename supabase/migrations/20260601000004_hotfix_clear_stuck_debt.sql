-- ─────────────────────────────────────────────────────────────────────────────
-- HOTFIX: Deploy checkout_clear_debt_direct AND immediately clear any stuck
-- outstanding debt that was already paid via a checkout order but not cleared
-- because the old checkout_settle_debt function had a logic error.
--
-- Paste this entire script into the Supabase SQL editor and run it.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Create checkout_clear_debt_direct ─────────────────────────────────────
-- (idempotent — safe to run multiple times)

CREATE OR REPLACE FUNCTION checkout_clear_debt_direct(
  p_user_id   UUID,
  p_amount    DECIMAL,
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

  UPDATE wallet_adjustments
  SET applied = true
  WHERE user_id = p_user_id
    AND type    = 'debt'
    AND applied = false;
END;
$$;

GRANT EXECUTE ON FUNCTION checkout_clear_debt_direct(UUID, DECIMAL, TEXT)
  TO authenticated;


-- ── 2. Retroactively clear debt for users who paid at checkout but were not
--       cleared because checkout_settle_debt had the balance-deduction bug.
--
-- Logic: find any wallet with debt_balance > 0 where the user also has
-- a completed order placed today (or recently) — those debts were charged
-- via the checkout total but never zeroed out.

DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT DISTINCT w.user_id, w.debt_balance
    FROM wallets w
    WHERE w.debt_balance > 0
      -- Only users who placed at least one order today
      AND EXISTS (
        SELECT 1 FROM orders o
        WHERE o.user_id = w.user_id
          AND o.status NOT IN ('cancelled')
          AND o.created_at >= NOW() - INTERVAL '7 days'
      )
  LOOP
    RAISE NOTICE 'Clearing $% debt for user %', r.debt_balance, r.user_id;

    UPDATE wallets
    SET debt_balance = 0,
        updated_at   = NOW()
    WHERE user_id = r.user_id;

    INSERT INTO wallet_transactions
      (user_id, amount, type, status, description)
    VALUES
      (r.user_id, -r.debt_balance, 'debt_clearance', 'completed',
       'Retroactive clearance — debt was charged at checkout but not recorded (hotfix)');

    UPDATE wallet_adjustments
    SET applied = true
    WHERE user_id = r.user_id
      AND type    = 'debt'
      AND applied = false;
  END LOOP;

  RAISE NOTICE 'Hotfix complete.';
END;
$$;
