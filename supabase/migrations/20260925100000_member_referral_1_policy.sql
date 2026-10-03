-- ============================================================================
-- HotBite Member Referral Rewards — 1/5 : versioned reward policy + helpers
-- ----------------------------------------------------------------------------
-- Two earning tiers only: direct (JMD $15) and second tier (JMD $2.50). Rewards
-- come only from genuine, paid, completed, non-refunded qualifying orders placed
-- by an ACTIVE paid member, and are unlocked by the earner completing 3 of their
-- own qualifying orders in a calendar month (Jamaica time). See migrations 3-4
-- for the ledger and engine. All money is integer JMD cents.
--
-- This subsystem is deliberately separate from the older, dormant
-- process_order_referral_earnings / earning_accounts path (0 rows live); that
-- path is left untouched and does not write to this ledger.
-- ============================================================================

-- Business-timezone calendar-month key (first day of the Jamaica month, as a
-- date). Timestamps are stored in UTC everywhere; only month bucketing uses the
-- Jamaica zone, matching the AI-staff metrics convention.
CREATE OR REPLACE FUNCTION public.hotbite_month_key(p_ts timestamptz)
RETURNS date
LANGUAGE sql IMMUTABLE
AS $$
  SELECT (date_trunc('month', p_ts AT TIME ZONE 'America/Jamaica'))::date;
$$;

-- Versioned policy. Changes apply PROSPECTIVELY: a new row with a later
-- effective_from; per-order snapshots (migration 3) pin the version that was in
-- force when the order qualified, so historical rewards never change.
CREATE TABLE IF NOT EXISTS public.referral_reward_policies (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  effective_from           timestamptz NOT NULL DEFAULT now(),
  enabled                  boolean NOT NULL DEFAULT true,
  direct_reward_cents      integer NOT NULL DEFAULT 1500,   -- JMD $15.00
  second_tier_reward_cents integer NOT NULL DEFAULT 250,    -- JMD $2.50
  min_order_value_cents    integer NOT NULL DEFAULT 0,      -- final paid value floor
  settlement_delay_hours   integer NOT NULL DEFAULT 72,     -- refund/adjustment window
  carry_forward_days       integer NOT NULL DEFAULT 60,     -- pending life after earning month
  monthly_cap_cents        integer NOT NULL DEFAULT 1000000,-- JMD $10,000 per earner per month
  personal_orders_required integer NOT NULL DEFAULT 3,      -- own orders to unlock
  currency                 text NOT NULL DEFAULT 'JMD',
  notes                    text,
  created_by               uuid REFERENCES users(id),
  created_at               timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rrp_direct_nonneg   CHECK (direct_reward_cents >= 0),
  CONSTRAINT rrp_second_nonneg   CHECK (second_tier_reward_cents >= 0),
  CONSTRAINT rrp_cap_pos         CHECK (monthly_cap_cents > 0),
  CONSTRAINT rrp_personal_pos    CHECK (personal_orders_required >= 1)
);

CREATE INDEX IF NOT EXISTS idx_rrp_effective_from ON public.referral_reward_policies(effective_from DESC);

ALTER TABLE public.referral_reward_policies ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rrp_admin_all ON public.referral_reward_policies;
CREATE POLICY rrp_admin_all ON public.referral_reward_policies FOR ALL
  USING (EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'admin'));
-- Authenticated users may READ the active policy (rates shown in the UI).
DROP POLICY IF EXISTS rrp_read_all ON public.referral_reward_policies;
CREATE POLICY rrp_read_all ON public.referral_reward_policies FOR SELECT
  USING (auth.uid() IS NOT NULL);

-- Seed the initial policy version (only if none exists).
INSERT INTO public.referral_reward_policies (effective_from, notes)
SELECT '2026-01-01T00:00:00Z', 'Initial HotBite Member Referral policy'
WHERE NOT EXISTS (SELECT 1 FROM public.referral_reward_policies);

-- The policy in force at a given instant (latest effective_from <= ts).
CREATE OR REPLACE FUNCTION public.referral_policy_at(p_ts timestamptz)
RETURNS public.referral_reward_policies
LANGUAGE sql STABLE
AS $$
  SELECT * FROM public.referral_reward_policies
  WHERE effective_from <= p_ts
  ORDER BY effective_from DESC
  LIMIT 1;
$$;

-- Convenience: the current policy.
CREATE OR REPLACE FUNCTION public.referral_policy_current()
RETURNS public.referral_reward_policies
LANGUAGE sql STABLE
AS $$ SELECT * FROM public.referral_policy_at(now()); $$;

GRANT EXECUTE ON FUNCTION public.hotbite_month_key(timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.referral_policy_at(timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.referral_policy_current() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
