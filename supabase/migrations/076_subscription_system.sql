-- 076: Uber One-style subscription system
-- Basic Plan: $12/month → 9 free deliveries
-- Pro Plan:   $24/month → 22 free deliveries

-- ── 0. Fix existing constraints for subscription compatibility ──────────────
-- Allow 'pending' status (needed while Stripe payment is processing)
ALTER TABLE user_subscriptions DROP CONSTRAINT IF EXISTS user_subscriptions_status_check;
ALTER TABLE user_subscriptions ADD CONSTRAINT user_subscriptions_status_check
  CHECK (status IN ('active', 'paused', 'cancelled', 'expired', 'pending'));

-- meal_plan_id must be nullable (delivery subscriptions aren't tied to meal plans)
ALTER TABLE user_subscriptions ALTER COLUMN meal_plan_id DROP NOT NULL;

-- ── 1. Add Stripe + plan_type columns to user_subscriptions ─────────────────
ALTER TABLE user_subscriptions
  ADD COLUMN IF NOT EXISTS plan_type TEXT CHECK (plan_type IN ('basic', 'pro')),
  ADD COLUMN IF NOT EXISTS stripe_subscription_id TEXT,
  ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT,
  ADD COLUMN IF NOT EXISTS current_period_end TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS deliveries_remaining INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS deliveries_used INT NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS service_fee_discount NUMERIC(4,2) NOT NULL DEFAULT 0.00;

-- Ensure deliveries_remaining can never go negative
ALTER TABLE user_subscriptions
  ADD CONSTRAINT deliveries_remaining_non_negative CHECK (deliveries_remaining >= 0);

-- Unique constraint on stripe_subscription_id for webhook idempotency
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_sub_stripe_id
  ON user_subscriptions (stripe_subscription_id) WHERE stripe_subscription_id IS NOT NULL;

-- Fast lookup: active subscription for a user
CREATE INDEX IF NOT EXISTS idx_user_sub_active
  ON user_subscriptions (user_id, status) WHERE status = 'active';

-- ── 2. Add eligible_for_subscription to restaurants ─────────────────────────
ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS eligible_for_subscription BOOLEAN NOT NULL DEFAULT true;

-- ── 3. Add subscription tracking to orders ──────────────────────────────────
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS subscription_id UUID REFERENCES user_subscriptions(id),
  ADD COLUMN IF NOT EXISTS subscription_delivery_used BOOLEAN NOT NULL DEFAULT false;

-- ── 4. Atomic decrement function — prevents race conditions & never goes <0 ─
CREATE OR REPLACE FUNCTION use_subscription_delivery(p_subscription_id UUID, p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_remaining INT;
BEGIN
  -- Lock the row to prevent concurrent decrements
  SELECT deliveries_remaining INTO v_remaining
  FROM user_subscriptions
  WHERE id = p_subscription_id
    AND status = 'active'
  FOR UPDATE;

  IF v_remaining IS NULL OR v_remaining <= 0 THEN
    RETURN false;
  END IF;

  UPDATE user_subscriptions
  SET deliveries_remaining = deliveries_remaining - 1,
      deliveries_used = deliveries_used + 1,
      updated_at = now()
  WHERE id = p_subscription_id;

  -- Mark order as using subscription delivery
  UPDATE orders
  SET subscription_id = p_subscription_id,
      subscription_delivery_used = true
  WHERE id = p_order_id;

  RETURN true;
END;
$$;

-- ── 5. App config keys ──────────────────────────────────────────────────────
INSERT INTO app_config (key, value, value_type, category, description) VALUES
  ('subscription_basic_price', '12.00', 'number', 'subscription', 'Monthly price for Basic plan (USD)'),
  ('subscription_basic_deliveries', '9', 'number', 'subscription', 'Free deliveries per month for Basic plan'),
  ('subscription_pro_price', '24.00', 'number', 'subscription', 'Monthly price for Pro plan (USD)'),
  ('subscription_pro_deliveries', '22', 'number', 'subscription', 'Free deliveries per month for Pro plan'),
  ('subscription_min_cart', '10.00', 'number', 'subscription', 'Minimum cart value to use subscription delivery'),
  ('subscription_service_fee_discount', '0.50', 'number', 'subscription', 'Service fee discount for subscribers (0.50 = 50% off)')
ON CONFLICT (key) DO NOTHING;

-- ── 6. RLS policies for service_role writes ─────────────────────────────────
-- Allow service_role to manage subscriptions (for edge functions)
CREATE POLICY sub_service_all ON user_subscriptions
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- Allow authenticated users to read their active subscription
DROP POLICY IF EXISTS subscriptions_select ON user_subscriptions;
CREATE POLICY subscriptions_select ON user_subscriptions
  FOR SELECT TO authenticated USING (user_id = auth.uid());

-- Admin can see all subscriptions
CREATE POLICY sub_admin_select ON user_subscriptions
  FOR SELECT TO authenticated USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
