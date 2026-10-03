-- ============================================================================
-- HotBite Member Referral Rewards — 3/5 : reward ledger + qualification helpers
-- ----------------------------------------------------------------------------
-- The reward ledger records one row per (order, earner, tier). A UNIQUE
-- constraint on that triple is the idempotency key: order retries, duplicated
-- webhooks and concurrent completions can never double-credit. Cap usage is a
-- per-(earner, earning_month) counter mutated under row lock for atomic,
-- concurrency-safe cap enforcement.
-- ============================================================================

-- 1. Qualification helpers ----------------------------------------------------
-- Final paid value of an order in cents = total_amount minus settled refunds.
CREATE OR REPLACE FUNCTION public.referral_order_final_value_cents(p_order_id uuid)
RETURNS integer
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT GREATEST(0, round((
    COALESCE((SELECT total_amount FROM orders WHERE id = p_order_id), 0)
    - COALESCE((SELECT sum(amount) FROM refunds
                WHERE order_id = p_order_id AND status IN ('approved','processed')), 0)
  ) * 100))::integer;
$$;

-- Is an order a "qualifying completed order" for the referral programme?
-- Delivered + not fully refunded + final paid value at/above the configured
-- minimum. Payment for a delivered order is assumed collected (prepaid or COD).
CREATE OR REPLACE FUNCTION public.referral_order_qualifies(p_order_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE o orders%ROWTYPE; v_final integer; v_min integer;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id;
  IF NOT FOUND OR o.status <> 'delivered' THEN RETURN false; END IF;
  IF COALESCE(o.payment_status,'') IN ('refunded','failed','cancelled') THEN RETURN false; END IF;
  v_final := public.referral_order_final_value_cents(p_order_id);
  IF v_final <= 0 THEN RETURN false; END IF;   -- fully refunded
  v_min := (public.referral_policy_at(COALESCE(o.delivered_at, o.created_at))).min_order_value_cents;
  RETURN v_final >= COALESCE(v_min, 0);
END;
$$;

-- Count an earner's OWN qualifying orders in a Jamaica calendar month.
CREATE OR REPLACE FUNCTION public.referral_personal_qualifying_count(p_user uuid, p_month date)
RETURNS integer
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT count(*)::integer FROM orders o
  WHERE o.user_id = p_user
    AND o.status = 'delivered'
    AND public.hotbite_month_key(COALESCE(o.delivered_at, o.created_at)) = p_month
    AND public.referral_order_qualifies(o.id);
$$;

-- 2. Reward ledger ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.referral_rewards (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  earner_id          uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  purchaser_id       uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  source_order_id    uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  tier               smallint NOT NULL,                    -- 1 = direct, 2 = second
  reward_cents       integer NOT NULL,
  currency           text NOT NULL DEFAULT 'JMD',
  status             text NOT NULL DEFAULT 'pending',      -- pending|credited|expired|reversed
  earning_month      date NOT NULL,                        -- Jamaica month of the order
  policy_id          uuid REFERENCES referral_reward_policies(id),
  order_value_cents  integer NOT NULL DEFAULT 0,           -- final paid value snapshot
  settle_at          timestamptz NOT NULL,                 -- creditable no earlier than this
  expires_at         timestamptz NOT NULL,                 -- pending dies after this
  wallet_txn_id      uuid,                                 -- set when credited
  reason             text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  credited_at        timestamptz,
  reversed_at        timestamptz,
  CONSTRAINT rr_tier_valid CHECK (tier IN (1,2)),
  CONSTRAINT rr_status_valid CHECK (status IN ('pending','credited','expired','reversed')),
  CONSTRAINT rr_reward_nonneg CHECK (reward_cents >= 0),
  CONSTRAINT rr_unique_order_earner_tier UNIQUE (source_order_id, earner_id, tier)
);
CREATE INDEX IF NOT EXISTS idx_rr_earner_status ON public.referral_rewards(earner_id, status);
CREATE INDEX IF NOT EXISTS idx_rr_earner_month ON public.referral_rewards(earner_id, earning_month);
CREATE INDEX IF NOT EXISTS idx_rr_source_order ON public.referral_rewards(source_order_id);
CREATE INDEX IF NOT EXISTS idx_rr_pending_settle ON public.referral_rewards(status, settle_at) WHERE status = 'pending';

ALTER TABLE public.referral_rewards ENABLE ROW LEVEL SECURITY;
-- The earner may read their own rewards; admins read all. No client writes.
DROP POLICY IF EXISTS rr_earner_select ON public.referral_rewards;
CREATE POLICY rr_earner_select ON public.referral_rewards FOR SELECT
  USING (earner_id = auth.uid()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'admin'));
DROP POLICY IF EXISTS rr_admin_write ON public.referral_rewards;
CREATE POLICY rr_admin_write ON public.referral_rewards FOR ALL
  USING (EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'admin'));

-- 3. Per-(earner, month) cap usage counter (atomic cap enforcement). ---------
CREATE TABLE IF NOT EXISTS public.referral_cap_usage (
  earner_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  earning_month date NOT NULL,
  earned_cents  integer NOT NULL DEFAULT 0,               -- active (pending+credited) earned this month
  updated_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (earner_id, earning_month),
  CONSTRAINT rcu_nonneg CHECK (earned_cents >= 0)
);
ALTER TABLE public.referral_cap_usage ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rcu_self_select ON public.referral_cap_usage;
CREATE POLICY rcu_self_select ON public.referral_cap_usage FOR SELECT
  USING (earner_id = auth.uid()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'admin'));

GRANT EXECUTE ON FUNCTION public.referral_order_final_value_cents(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.referral_order_qualifies(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.referral_personal_qualifying_count(uuid,date) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
