-- ====================================================================
-- Migration 068: Referral Earning System
-- 3-tier earning system: Customer → Builder → Leader
-- Credits flow into wallet cashback_balance for spending on orders
-- ====================================================================

-- ============================================================
-- 1. EARNING ACCOUNTS — one per user, tracks tier + lifetime stats
-- ============================================================
CREATE TABLE IF NOT EXISTS public.earning_accounts (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  tier            TEXT NOT NULL DEFAULT 'customer'
                    CHECK (tier IN ('customer', 'builder', 'leader')),
  -- Lifetime stats
  total_earned        DECIMAL(12,2) NOT NULL DEFAULT 0,
  total_direct_refs   INT NOT NULL DEFAULT 0,
  total_indirect_refs INT NOT NULL DEFAULT 0,
  total_orders_generated INT NOT NULL DEFAULT 0,
  -- Monthly stats (reset monthly by cron or checked per-call)
  monthly_earned      DECIMAL(12,2) NOT NULL DEFAULT 0,
  monthly_orders      INT NOT NULL DEFAULT 0,
  month_key           TEXT NOT NULL DEFAULT to_char(now(), 'YYYY-MM'),
  -- Timestamps
  tier_updated_at TIMESTAMPTZ DEFAULT now(),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_earning_accounts_user_id
  ON public.earning_accounts(user_id);

ALTER TABLE public.earning_accounts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_earning_account" ON public.earning_accounts
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "admin_all_earning_accounts" ON public.earning_accounts
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

GRANT SELECT, INSERT, UPDATE ON public.earning_accounts TO authenticated;

-- ============================================================
-- 2. EARNING TRANSACTIONS — per-event credit log
-- ============================================================
CREATE TABLE IF NOT EXISTS public.earning_transactions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  type        TEXT NOT NULL CHECK (type IN (
    'signup_bonus',          -- $2 when referral signs up
    'referred_first_order',  -- bonus unlocked after referred user's 1st order
    'direct_order',          -- $0.30 per order from direct referral
    'indirect_order',        -- $0.10 per order from indirect referral (builder+)
    'volume_bonus',          -- monthly volume milestone
    'restaurant_referral',   -- restaurant referral ad credits
    'expired',               -- credit expiry deduction
    'adjustment'             -- admin manual adjustment
  )),
  amount      DECIMAL(12,2) NOT NULL,
  -- Context references
  source_user_id UUID REFERENCES public.users(id),  -- who generated this earning
  order_id       UUID REFERENCES public.orders(id),
  description    TEXT DEFAULT '',
  -- Expiry tracking
  expires_at     TIMESTAMPTZ,  -- NULL = never expires
  is_expired     BOOLEAN NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_earning_transactions_user_id
  ON public.earning_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_earning_transactions_type
  ON public.earning_transactions(type);
CREATE INDEX IF NOT EXISTS idx_earning_transactions_expires_at
  ON public.earning_transactions(expires_at) WHERE NOT is_expired;
CREATE INDEX IF NOT EXISTS idx_earning_transactions_source_user
  ON public.earning_transactions(source_user_id);

ALTER TABLE public.earning_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_earning_txns" ON public.earning_transactions
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "admin_all_earning_txns" ON public.earning_transactions
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

GRANT SELECT, INSERT ON public.earning_transactions TO authenticated;

-- ============================================================
-- 3. APP_CONFIG rows for earning system (admin-tunable)
-- ============================================================
INSERT INTO public.app_config (key, value, value_type, category, description) VALUES
  -- Signup rewards
  ('earning_referrer_signup_bonus',  '2.00',  'number', 'earning', 'Referrer gets $X when friend signs up'),
  ('earning_referred_first_order',   '3.00',  'number', 'earning', 'Referred friend gets $X off first order'),
  -- Per-order commissions
  ('earning_direct_order_rate',      '0.30',  'number', 'earning', '$ per order from direct referrals'),
  ('earning_indirect_order_rate',    '0.10',  'number', 'earning', '$ per order from indirect referrals (builder+)'),
  -- Tier thresholds
  ('earning_builder_min_refs',       '5',     'number', 'earning', 'Min active referrals to become Builder'),
  ('earning_builder_min_orders',     '50',    'number', 'earning', 'OR min orders generated to become Builder'),
  ('earning_leader_min_refs',        '15',    'number', 'earning', 'Min active referrals to become Leader'),
  ('earning_leader_min_orders',      '150',   'number', 'earning', 'OR min orders generated to become Leader'),
  -- Volume bonuses (Leader tier)
  ('earning_volume_bonus_300',       '25.00', 'number', 'earning', 'Monthly bonus at 300 orders'),
  ('earning_volume_bonus_1000',     '100.00', 'number', 'earning', 'Monthly bonus at 1000 orders'),
  ('earning_volume_bonus_3000',     '250.00', 'number', 'earning', 'Monthly bonus at 3000 orders'),
  -- Controls / limits
  ('earning_monthly_cap',           '300.00', 'number', 'earning', 'Max credits per user per month'),
  ('earning_credit_expiry_days',    '21',     'number', 'earning', 'Credits expire after N days'),
  ('earning_min_order_to_use',      '10.00',  'number', 'earning', 'Min order total to use credits'),
  ('earning_max_credit_pct',        '0.50',   'number', 'earning', 'Max % of order payable with credits'),
  -- Restaurant referral
  ('earning_restaurant_ref_credits','50.00',  'number', 'earning', 'Ad credits for referring a restaurant'),
  ('earning_restaurant_ref_commission_discount', '0.02', 'number', 'earning', 'Commission discount for restaurant referral')
ON CONFLICT (key) DO NOTHING;

-- ============================================================
-- 4. CORE RPC: credit_earning — atomically credits user wallet
--    and logs the earning transaction
-- ============================================================
CREATE OR REPLACE FUNCTION public.credit_earning(
  p_user_id       UUID,
  p_amount        DECIMAL,
  p_type          TEXT,
  p_source_user   UUID DEFAULT NULL,
  p_order_id      UUID DEFAULT NULL,
  p_description   TEXT DEFAULT '',
  p_expiry_days   INT  DEFAULT NULL
)
RETURNS UUID  -- returns the earning_transaction id
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_monthly_cap     DECIMAL;
  v_current_monthly DECIMAL;
  v_month_key       TEXT := to_char(now(), 'YYYY-MM');
  v_final_amount    DECIMAL;
  v_expires_at      TIMESTAMPTZ;
  v_txn_id          UUID;
  v_expiry_days     INT;
BEGIN
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  -- Get monthly cap from config
  SELECT COALESCE(
    (SELECT value::decimal FROM app_config WHERE key = 'earning_monthly_cap'),
    300.00
  ) INTO v_monthly_cap;

  -- Get or reset monthly earned for this user
  INSERT INTO earning_accounts (user_id, monthly_earned, month_key)
  VALUES (p_user_id, 0, v_month_key)
  ON CONFLICT (user_id) DO UPDATE SET
    monthly_earned = CASE
      WHEN earning_accounts.month_key != v_month_key THEN 0
      ELSE earning_accounts.monthly_earned
    END,
    month_key = v_month_key,
    updated_at = now();

  SELECT monthly_earned INTO v_current_monthly
  FROM earning_accounts WHERE user_id = p_user_id;

  -- Cap the amount so user doesn't exceed monthly limit
  v_final_amount := LEAST(p_amount, v_monthly_cap - v_current_monthly);
  IF v_final_amount <= 0 THEN
    RAISE EXCEPTION 'Monthly earning cap reached';
  END IF;

  -- Calculate expiry
  IF p_expiry_days IS NOT NULL THEN
    v_expiry_days := p_expiry_days;
  ELSE
    SELECT COALESCE(
      (SELECT value::int FROM app_config WHERE key = 'earning_credit_expiry_days'),
      21
    ) INTO v_expiry_days;
  END IF;
  v_expires_at := now() + (v_expiry_days || ' days')::interval;

  -- Insert earning transaction
  INSERT INTO earning_transactions (
    user_id, type, amount, source_user_id, order_id,
    description, expires_at
  ) VALUES (
    p_user_id, p_type, v_final_amount, p_source_user, p_order_id,
    p_description, v_expires_at
  ) RETURNING id INTO v_txn_id;

  -- Credit user's wallet cashback_balance
  INSERT INTO wallets (user_id, balance, cashback_balance)
  VALUES (p_user_id, 0, v_final_amount)
  ON CONFLICT (user_id) DO UPDATE SET
    cashback_balance = wallets.cashback_balance + v_final_amount,
    updated_at = now();

  -- Update earning account stats
  UPDATE earning_accounts SET
    total_earned = total_earned + v_final_amount,
    monthly_earned = monthly_earned + v_final_amount,
    updated_at = now()
  WHERE user_id = p_user_id;

  -- Log wallet transaction
  INSERT INTO wallet_transactions (
    user_id, amount, type, payment_method, status, order_id, description
  ) VALUES (
    p_user_id, v_final_amount, 'cashback', 'system', 'completed',
    p_order_id,
    'Referral earning: ' || p_description
  );

  RETURN v_txn_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.credit_earning(UUID, DECIMAL, TEXT, UUID, UUID, TEXT, INT) TO authenticated;

-- ============================================================
-- 5. RPC: update_earning_tier — recalculate tier for a user
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_earning_tier(p_user_id UUID)
RETURNS TEXT  -- returns the new tier
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account           earning_accounts;
  v_builder_refs      INT;
  v_builder_orders    INT;
  v_leader_refs       INT;
  v_leader_orders     INT;
  v_new_tier          TEXT;
BEGIN
  SELECT * INTO v_account FROM earning_accounts WHERE user_id = p_user_id;
  IF v_account IS NULL THEN
    -- Create account if missing
    INSERT INTO earning_accounts (user_id) VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN 'customer';
  END IF;

  -- Get thresholds from config
  SELECT COALESCE((SELECT value::int FROM app_config WHERE key = 'earning_builder_min_refs'), 5)
    INTO v_builder_refs;
  SELECT COALESCE((SELECT value::int FROM app_config WHERE key = 'earning_builder_min_orders'), 50)
    INTO v_builder_orders;
  SELECT COALESCE((SELECT value::int FROM app_config WHERE key = 'earning_leader_min_refs'), 15)
    INTO v_leader_refs;
  SELECT COALESCE((SELECT value::int FROM app_config WHERE key = 'earning_leader_min_orders'), 150)
    INTO v_leader_orders;

  -- Determine tier
  IF v_account.total_direct_refs >= v_leader_refs
     OR v_account.total_orders_generated >= v_leader_orders THEN
    v_new_tier := 'leader';
  ELSIF v_account.total_direct_refs >= v_builder_refs
     OR v_account.total_orders_generated >= v_builder_orders THEN
    v_new_tier := 'builder';
  ELSE
    v_new_tier := 'customer';
  END IF;

  -- Update if changed
  IF v_new_tier IS DISTINCT FROM v_account.tier THEN
    UPDATE earning_accounts SET
      tier = v_new_tier,
      tier_updated_at = now(),
      updated_at = now()
    WHERE user_id = p_user_id;
  END IF;

  RETURN v_new_tier;
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_earning_tier(UUID) TO authenticated;

-- ============================================================
-- 6. RPC: expire_old_credits — called by cron or admin
-- ============================================================
CREATE OR REPLACE FUNCTION public.expire_old_credits()
RETURNS INT  -- returns number of expired transactions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rec RECORD;
  v_count INT := 0;
BEGIN
  FOR v_rec IN
    SELECT id, user_id, amount
    FROM earning_transactions
    WHERE NOT is_expired
      AND expires_at IS NOT NULL
      AND expires_at < now()
  LOOP
    -- Mark as expired
    UPDATE earning_transactions SET is_expired = true WHERE id = v_rec.id;

    -- Deduct from wallet cashback (but don't go below 0)
    UPDATE wallets SET
      cashback_balance = GREATEST(0, cashback_balance - v_rec.amount),
      updated_at = now()
    WHERE user_id = v_rec.user_id;

    -- Log the expiry
    INSERT INTO earning_transactions (
      user_id, type, amount, description, is_expired
    ) VALUES (
      v_rec.user_id, 'expired', -v_rec.amount,
      'Credit expired', true
    );

    INSERT INTO wallet_transactions (
      user_id, amount, type, payment_method, status, description
    ) VALUES (
      v_rec.user_id, -v_rec.amount, 'cashback', 'system', 'completed',
      'Referral credit expired'
    );

    v_count := v_count + 1;
  END LOOP;

  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.expire_old_credits() TO authenticated;

-- ============================================================
-- 7. RPC: process_order_referral_earnings
--    Called after an order is delivered. Credits referrer(s).
-- ============================================================
CREATE OR REPLACE FUNCTION public.process_order_referral_earnings(
  p_order_id UUID,
  p_customer_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_referrer_id       UUID;
  v_indirect_referrer UUID;
  v_direct_rate       DECIMAL;
  v_indirect_rate     DECIMAL;
  v_referrer_tier     TEXT;
  v_result            JSONB := '{}'::jsonb;
BEGIN
  -- Find the direct referrer of this customer
  SELECT referred_by INTO v_referrer_id
  FROM users WHERE id = p_customer_id;

  IF v_referrer_id IS NULL THEN
    RETURN jsonb_build_object('credited', false, 'reason', 'no_referrer');
  END IF;

  -- Get config rates
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_direct_order_rate'), 0.30)
    INTO v_direct_rate;
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_indirect_order_rate'), 0.10)
    INTO v_indirect_rate;

  -- Credit direct referrer
  BEGIN
    PERFORM credit_earning(
      v_referrer_id,
      v_direct_rate,
      'direct_order',
      p_customer_id,
      p_order_id,
      'Order commission from direct referral'
    );
  EXCEPTION WHEN OTHERS THEN
    -- Monthly cap reached, ignore
    NULL;
  END;

  -- Update direct referrer stats
  UPDATE earning_accounts SET
    total_orders_generated = total_orders_generated + 1,
    monthly_orders = CASE
      WHEN month_key = to_char(now(), 'YYYY-MM') THEN monthly_orders + 1
      ELSE 1
    END,
    month_key = to_char(now(), 'YYYY-MM'),
    updated_at = now()
  WHERE user_id = v_referrer_id;

  -- Re-evaluate tier
  PERFORM update_earning_tier(v_referrer_id);

  v_result := jsonb_build_object(
    'credited', true,
    'direct_referrer', v_referrer_id,
    'direct_amount', v_direct_rate
  );

  -- Check for indirect referrer (builder+ tier only, 1 level)
  SELECT referred_by INTO v_indirect_referrer
  FROM users WHERE id = v_referrer_id;

  IF v_indirect_referrer IS NOT NULL THEN
    -- Only credit if indirect referrer is builder or leader
    SELECT tier INTO v_referrer_tier
    FROM earning_accounts WHERE user_id = v_indirect_referrer;

    IF v_referrer_tier IN ('builder', 'leader') THEN
      BEGIN
        PERFORM credit_earning(
          v_indirect_referrer,
          v_indirect_rate,
          'indirect_order',
          p_customer_id,
          p_order_id,
          'Order commission from indirect referral'
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;

      -- Update indirect referrer stats
      UPDATE earning_accounts SET
        total_indirect_refs = CASE
          WHEN NOT EXISTS (
            SELECT 1 FROM earning_transactions
            WHERE user_id = v_indirect_referrer
              AND source_user_id = p_customer_id
              AND type = 'indirect_order'
              AND id != (SELECT id FROM earning_transactions ORDER BY created_at DESC LIMIT 1)
          ) THEN total_indirect_refs + 1
          ELSE total_indirect_refs
        END,
        updated_at = now()
      WHERE user_id = v_indirect_referrer;

      PERFORM update_earning_tier(v_indirect_referrer);

      v_result := v_result || jsonb_build_object(
        'indirect_referrer', v_indirect_referrer,
        'indirect_amount', v_indirect_rate
      );
    END IF;
  END IF;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_order_referral_earnings(UUID, UUID) TO authenticated;

-- ============================================================
-- 8. RPC: process_signup_referral_bonus
--    Called when a referred user completes their first order.
-- ============================================================
CREATE OR REPLACE FUNCTION public.process_signup_referral_bonus(
  p_referred_user_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_referrer_id       UUID;
  v_referrer_bonus    DECIMAL;
  v_referred_bonus    DECIMAL;
  v_already_rewarded  BOOLEAN;
BEGIN
  -- Find referrer
  SELECT referred_by INTO v_referrer_id
  FROM users WHERE id = p_referred_user_id;

  IF v_referrer_id IS NULL THEN
    RETURN jsonb_build_object('credited', false, 'reason', 'no_referrer');
  END IF;

  -- Check if already rewarded
  SELECT reward_given INTO v_already_rewarded
  FROM referrals
  WHERE referrer_id = v_referrer_id AND referred_id = p_referred_user_id
  LIMIT 1;

  IF v_already_rewarded IS TRUE THEN
    RETURN jsonb_build_object('credited', false, 'reason', 'already_rewarded');
  END IF;

  -- Get bonus amounts from config
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_referrer_signup_bonus'), 2.00)
    INTO v_referrer_bonus;
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_referred_first_order'), 3.00)
    INTO v_referred_bonus;

  -- Credit referrer $2
  BEGIN
    PERFORM credit_earning(
      v_referrer_id,
      v_referrer_bonus,
      'signup_bonus',
      p_referred_user_id,
      NULL,
      'Signup bonus: friend completed first order'
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Credit referred user $3
  BEGIN
    PERFORM credit_earning(
      p_referred_user_id,
      v_referred_bonus,
      'referred_first_order',
      v_referrer_id,
      NULL,
      'Welcome bonus: first order discount'
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Mark referral as rewarded
  UPDATE referrals SET reward_given = true
  WHERE referrer_id = v_referrer_id AND referred_id = p_referred_user_id;

  -- Update referrer's direct ref count
  UPDATE earning_accounts SET
    total_direct_refs = total_direct_refs + 1,
    updated_at = now()
  WHERE user_id = v_referrer_id;

  PERFORM update_earning_tier(v_referrer_id);

  RETURN jsonb_build_object(
    'credited', true,
    'referrer_bonus', v_referrer_bonus,
    'referred_bonus', v_referred_bonus
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_signup_referral_bonus(UUID) TO authenticated;

-- ============================================================
-- 9. RPC: process_volume_bonus — check & award monthly milestones
-- ============================================================
CREATE OR REPLACE FUNCTION public.process_volume_bonus(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_account       earning_accounts;
  v_month_key     TEXT := to_char(now(), 'YYYY-MM');
  v_bonus_300     DECIMAL;
  v_bonus_1000    DECIMAL;
  v_bonus_3000    DECIMAL;
  v_awarded       DECIMAL := 0;
  v_already       BOOLEAN;
BEGIN
  SELECT * INTO v_account
  FROM earning_accounts WHERE user_id = p_user_id;

  IF v_account IS NULL OR v_account.tier != 'leader' THEN
    RETURN jsonb_build_object('awarded', 0, 'reason', 'not_leader');
  END IF;

  -- Ensure month_key is current
  IF v_account.month_key != v_month_key THEN
    UPDATE earning_accounts SET
      monthly_orders = 0, monthly_earned = 0, month_key = v_month_key
    WHERE user_id = p_user_id;
    v_account.monthly_orders := 0;
  END IF;

  -- Get bonus thresholds
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_volume_bonus_300'), 25.00)
    INTO v_bonus_300;
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_volume_bonus_1000'), 100.00)
    INTO v_bonus_1000;
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_volume_bonus_3000'), 250.00)
    INTO v_bonus_3000;

  -- Check if 3000 milestone already awarded this month
  IF v_account.monthly_orders >= 3000 THEN
    SELECT EXISTS (
      SELECT 1 FROM earning_transactions
      WHERE user_id = p_user_id AND type = 'volume_bonus'
        AND description LIKE '%3000%'
        AND created_at >= date_trunc('month', now())
    ) INTO v_already;
    IF NOT v_already THEN
      PERFORM credit_earning(p_user_id, v_bonus_3000, 'volume_bonus', NULL, NULL,
        'Volume bonus: 3000 monthly orders');
      v_awarded := v_awarded + v_bonus_3000;
    END IF;
  ELSIF v_account.monthly_orders >= 1000 THEN
    SELECT EXISTS (
      SELECT 1 FROM earning_transactions
      WHERE user_id = p_user_id AND type = 'volume_bonus'
        AND description LIKE '%1000%'
        AND created_at >= date_trunc('month', now())
    ) INTO v_already;
    IF NOT v_already THEN
      PERFORM credit_earning(p_user_id, v_bonus_1000, 'volume_bonus', NULL, NULL,
        'Volume bonus: 1000 monthly orders');
      v_awarded := v_awarded + v_bonus_1000;
    END IF;
  ELSIF v_account.monthly_orders >= 300 THEN
    SELECT EXISTS (
      SELECT 1 FROM earning_transactions
      WHERE user_id = p_user_id AND type = 'volume_bonus'
        AND description LIKE '%300 monthly%'
        AND created_at >= date_trunc('month', now())
    ) INTO v_already;
    IF NOT v_already THEN
      PERFORM credit_earning(p_user_id, v_bonus_300, 'volume_bonus', NULL, NULL,
        'Volume bonus: 300 monthly orders');
      v_awarded := v_awarded + v_bonus_300;
    END IF;
  END IF;

  RETURN jsonb_build_object('awarded', v_awarded, 'monthly_orders', v_account.monthly_orders);
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_volume_bonus(UUID) TO authenticated;
