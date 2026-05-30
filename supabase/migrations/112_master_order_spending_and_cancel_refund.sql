-- =============================================================================
-- Migration 112: Multi-restaurant order — spending tracking & cancel refunds
--
-- Problems fixed:
--   1. When a master_order is DELIVERED → cashback, loyalty points, and referral
--      earnings are not awarded because the existing triggers fire on the `orders`
--      table only.  Multi-restaurant orders live in `master_orders`.
--
--   2. When a master_order is CANCELLED and was paid via wallet → the wallet
--      balance is not restored.
--
-- Technical constraint: wallet_transactions.order_id, loyalty_transactions.order_id
-- and earning_transactions.order_id are all FK → orders.id.  Passing a
-- master_orders UUID would violate the FK, so we store NULL as order_id and
-- embed the reference in the description field instead.
-- =============================================================================


-- ── 1. Helper: award cashback for a delivered master order ────────────────────
CREATE OR REPLACE FUNCTION fn_cashback_master_order(
  p_user_id         UUID,
  p_master_order_id UUID,
  p_subtotal        DECIMAL
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_cashback DECIMAL;
BEGIN
  v_cashback := ROUND(p_subtotal * 0.03, 2);
  IF v_cashback <= 0 THEN RETURN; END IF;

  INSERT INTO wallets (user_id, cashback_balance)
    VALUES (p_user_id, v_cashback)
  ON CONFLICT (user_id) DO UPDATE SET
    cashback_balance = wallets.cashback_balance + v_cashback,
    updated_at       = NOW();

  -- order_id is intentionally NULL: FK is to orders, not master_orders
  INSERT INTO wallet_transactions
    (user_id, amount, type, payment_method, status, description)
  VALUES (
    p_user_id, v_cashback, 'cashback', 'system', 'completed',
    'Cashback – multi-restaurant order #' || UPPER(LEFT(p_master_order_id::text, 8))
  );
END;
$$;


-- ── 2. Helper: process referral earnings for a delivered master order ─────────
-- Replicates process_order_referral_earnings() but passes NULL for order_id
-- so the FK on earning_transactions / wallet_transactions is satisfied.
CREATE OR REPLACE FUNCTION fn_referral_master_order(
  p_master_order_id UUID,
  p_customer_id     UUID
)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_referrer_id       UUID;
  v_indirect_referrer UUID;
  v_direct_rate       DECIMAL;
  v_indirect_rate     DECIMAL;
  v_referrer_tier     TEXT;
BEGIN
  SELECT referred_by INTO v_referrer_id FROM users WHERE id = p_customer_id;
  IF v_referrer_id IS NULL THEN RETURN; END IF;

  SELECT COALESCE(
    (SELECT value::decimal FROM app_config WHERE key = 'earning_direct_order_rate'), 0.30
  ) INTO v_direct_rate;

  SELECT COALESCE(
    (SELECT value::decimal FROM app_config WHERE key = 'earning_indirect_order_rate'), 0.10
  ) INTO v_indirect_rate;

  -- Credit direct referrer (suppress cap errors — just skip)
  BEGIN
    PERFORM credit_earning(
      v_referrer_id,
      v_direct_rate,
      'direct_order',
      p_customer_id,
      NULL,   -- NULL because master_orders.id is not in orders table
      'Commission from multi-restaurant order #' || UPPER(LEFT(p_master_order_id::text, 8))
    );
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  -- Update referrer stats
  UPDATE earning_accounts SET
    total_orders_generated = total_orders_generated + 1,
    monthly_orders = CASE
      WHEN month_key = to_char(NOW(), 'YYYY-MM') THEN monthly_orders + 1
      ELSE 1
    END,
    month_key  = to_char(NOW(), 'YYYY-MM'),
    updated_at = NOW()
  WHERE user_id = v_referrer_id;

  PERFORM update_earning_tier(v_referrer_id);

  -- Indirect referrer (builder / leader tier only)
  SELECT referred_by INTO v_indirect_referrer FROM users WHERE id = v_referrer_id;
  IF v_indirect_referrer IS NOT NULL THEN
    SELECT tier INTO v_referrer_tier
    FROM earning_accounts WHERE user_id = v_indirect_referrer;

    IF v_referrer_tier IN ('builder', 'leader') THEN
      BEGIN
        PERFORM credit_earning(
          v_indirect_referrer,
          v_indirect_rate,
          'indirect_order',
          p_customer_id,
          NULL,
          'Indirect commission from multi-restaurant order #' || UPPER(LEFT(p_master_order_id::text, 8))
        );
      EXCEPTION WHEN OTHERS THEN NULL;
      END;
    END IF;
  END IF;
END;
$$;


-- ── 3. Trigger function: award all earnings on delivery ───────────────────────
CREATE OR REPLACE FUNCTION fn_master_order_delivered()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_points_per  DECIMAL;
  v_base_points INT;
BEGIN
  -- Guard: only fire on the transition into 'delivered'
  IF NEW.status <> 'delivered' OR OLD.status = 'delivered' THEN
    RETURN NEW;
  END IF;

  -- 1. Wallet cashback (3 % of subtotal, consistent with single-order trigger)
  IF COALESCE(NEW.subtotal, 0) > 0 THEN
    BEGIN
      PERFORM fn_cashback_master_order(NEW.customer_id, NEW.id, NEW.subtotal);
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  -- 2. Loyalty points  (points_per_100 from app_config, default 10 pts / $100)
  SELECT COALESCE(
    (SELECT value::decimal FROM app_config WHERE key = 'loyalty_points_per_100'), 10
  ) INTO v_points_per;

  v_base_points := FLOOR(COALESCE(NEW.total_amount, 0) / 100.0 * v_points_per)::INT;
  IF v_base_points > 0 THEN
    BEGIN
      PERFORM add_loyalty_points(
        NEW.customer_id,
        v_base_points,
        NULL,   -- order_id NULL — FK constraint would reject master_orders UUID
        'earn',
        'Points earned – multi-restaurant order #' || UPPER(LEFT(NEW.id::text, 8))
      );
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  -- 3. Referral earnings (fire-and-forget)
  BEGIN
    PERFORM fn_referral_master_order(NEW.id, NEW.customer_id);
  EXCEPTION WHEN OTHERS THEN NULL;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_master_order_delivered ON master_orders;
CREATE TRIGGER trg_master_order_delivered
  AFTER UPDATE OF status ON master_orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered')
  EXECUTE FUNCTION fn_master_order_delivered();


-- ── 4. Trigger function: refund wallet on cancellation ───────────────────────
CREATE OR REPLACE FUNCTION fn_master_order_cancelled()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Guard: only fire on the transition into 'cancelled'
  IF NEW.status <> 'cancelled' OR OLD.status = 'cancelled' THEN
    RETURN NEW;
  END IF;

  -- Only refund wallet payments that were already collected
  IF NEW.payment_method = 'wallet' AND NEW.payment_status = 'completed' THEN

    -- Restore the full order amount to the customer's main wallet balance
    INSERT INTO wallets (user_id, balance)
      VALUES (NEW.customer_id, NEW.total_amount)
    ON CONFLICT (user_id) DO UPDATE SET
      balance    = wallets.balance + NEW.total_amount,
      updated_at = NOW();

    -- Record the refund so it appears in wallet history
    INSERT INTO wallet_transactions
      (user_id, amount, type, payment_method, status, description)
    VALUES (
      NEW.customer_id,
      NEW.total_amount,
      'refund',
      'wallet',
      'completed',
      'Refund – cancelled multi-restaurant order #' || UPPER(LEFT(NEW.id::text, 8))
    );

    -- Stamp payment_status = 'refunded' so Flutter / admin can see the state
    UPDATE master_orders
    SET payment_status = 'refunded', updated_at = NOW()
    WHERE id = NEW.id;

  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_master_order_cancelled ON master_orders;
CREATE TRIGGER trg_master_order_cancelled
  AFTER UPDATE OF status ON master_orders
  FOR EACH ROW
  WHEN (NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled')
  EXECUTE FUNCTION fn_master_order_cancelled();
