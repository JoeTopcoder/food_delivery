-- ============================================================================
-- Switch the member-referral program from PER-ORDER cashback to a one-time
-- MEMBERSHIP SIGNUP BOUNTY: the referrer is paid the moment a referred user
-- activates a paid membership; the old $65/$35-per-order accrual is turned off.
-- Reuses the existing policy amounts (direct_reward_cents / second_tier_reward_cents),
-- the monthly cap (referral_cap_usage), and the same wallet-credit convention.
-- ============================================================================

-- ── Schema: allow membership-sourced rewards (source_order_id becomes optional) ──
ALTER TABLE public.referral_rewards ALTER COLUMN source_order_id DROP NOT NULL;
ALTER TABLE public.referral_rewards
  ADD COLUMN IF NOT EXISTS source_membership_id uuid
  REFERENCES public.customer_memberships(id) ON DELETE SET NULL;
CREATE UNIQUE INDEX IF NOT EXISTS rr_unique_membership_earner_tier
  ON public.referral_rewards(source_membership_id, earner_id, tier)
  WHERE source_membership_id IS NOT NULL;

-- ── Grant helper: cap-aware, idempotent, credits the wallet immediately ─────
CREATE OR REPLACE FUNCTION public._referral_grant_membership(
  p_earner uuid, p_purchaser uuid, p_membership uuid, p_tier smallint,
  p_amount int, p_month date, p_policy uuid)
RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_used int; v_cap int; v_remaining int; v_grant int; v_reason text; v_txn uuid;
BEGIN
  -- Never pay yourself for your own signup.
  IF p_earner IS NULL OR p_earner = p_purchaser THEN RETURN 0; END IF;

  -- Idempotent: one reward per (membership, earner, tier).
  IF EXISTS (SELECT 1 FROM referral_rewards
             WHERE source_membership_id = p_membership AND earner_id = p_earner AND tier = p_tier) THEN
    RETURN 0;
  END IF;

  v_cap := (public.referral_policy_current()).monthly_cap_cents;

  INSERT INTO referral_cap_usage(earner_id, earning_month, earned_cents)
  VALUES (p_earner, p_month, 0)
  ON CONFLICT (earner_id, earning_month) DO NOTHING;

  SELECT earned_cents INTO v_used FROM referral_cap_usage
  WHERE earner_id = p_earner AND earning_month = p_month FOR UPDATE;

  v_remaining := GREATEST(0, v_cap - COALESCE(v_used,0));
  v_grant := LEAST(p_amount, v_remaining);

  IF v_grant <= 0 THEN
    -- Record a zero row for audit so the cap ceiling is visible, no wallet move.
    INSERT INTO referral_rewards(
      earner_id, purchaser_id, source_membership_id, tier, reward_cents, status,
      earning_month, policy_id, settle_at, expires_at, reason, credited_at)
    VALUES (p_earner, p_purchaser, p_membership, p_tier, 0, 'credited',
            p_month, p_policy, now(), now() + interval '10 years',
            'tier'||p_tier||'_capped', now())
    ON CONFLICT (source_membership_id, earner_id, tier)
      WHERE source_membership_id IS NOT NULL DO NOTHING;
    RETURN 0;
  END IF;

  v_reason := CASE WHEN v_grant < p_amount
                   THEN 'tier'||p_tier||'_membership_capped'
                   ELSE 'tier'||p_tier||'_membership' END;

  -- Credit the earner's wallet immediately (cashback), same as unlock path.
  INSERT INTO wallets(user_id, balance, cashback_balance)
    VALUES (p_earner, 0, 0) ON CONFLICT (user_id) DO NOTHING;
  UPDATE wallets SET balance = COALESCE(balance,0) + (v_grant/100.0), updated_at = now()
    WHERE user_id = p_earner;
  INSERT INTO wallet_transactions(user_id, amount, type, payment_method, status, description)
    VALUES (p_earner, (v_grant/100.0), 'cashback', 'wallet', 'completed',
            'Membership referral bounty (tier '||p_tier||')')
    RETURNING id INTO v_txn;

  INSERT INTO referral_rewards(
    earner_id, purchaser_id, source_membership_id, tier, reward_cents, status,
    earning_month, policy_id, settle_at, expires_at, reason, credited_at, wallet_txn_id)
  VALUES (p_earner, p_purchaser, p_membership, p_tier, v_grant, 'credited',
          p_month, p_policy, now(), now() + interval '10 years',
          v_reason, now(), v_txn)
  ON CONFLICT (source_membership_id, earner_id, tier)
    WHERE source_membership_id IS NOT NULL DO NOTHING;

  UPDATE referral_cap_usage SET earned_cents = earned_cents + v_grant, updated_at = now()
  WHERE earner_id = p_earner AND earning_month = p_month;

  RETURN v_grant;
END; $$;

-- ── Award the signup bounty for one membership (tier 1 + tier 2) ────────────
CREATE OR REPLACE FUNCTION public.referral_award_for_membership(p_membership_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  m   customer_memberships%ROWTYPE;
  pol referral_reward_policies%ROWTYPE;
  v_month date; v_t1 uuid; v_t2 uuid; v_g1 int := 0; v_g2 int := 0;
BEGIN
  SELECT * INTO m FROM customer_memberships WHERE id = p_membership_id;
  IF NOT FOUND OR m.status <> 'active' THEN
    RETURN jsonb_build_object('ok',false,'reason','no_active_membership');
  END IF;

  pol := public.referral_policy_at(m.created_at);
  IF pol.id IS NULL OR NOT pol.enabled THEN
    RETURN jsonb_build_object('ok',false,'reason','programme_disabled');
  END IF;

  v_month := public.hotbite_month_key(m.created_at);

  -- Tier 1: the new member's referrer at signup time.
  v_t1 := public.referral_referrer_at(m.user_id, m.created_at);
  IF v_t1 IS NOT NULL THEN
    v_g1 := public._referral_grant_membership(
              v_t1, m.user_id, p_membership_id, 1::smallint, pol.direct_reward_cents, v_month, pol.id);
    -- Tier 2: that referrer's own referrer.
    v_t2 := public.referral_referrer_at(v_t1, m.created_at);
    IF v_t2 IS NOT NULL THEN
      v_g2 := public._referral_grant_membership(
                v_t2, m.user_id, p_membership_id, 2::smallint, pol.second_tier_reward_cents, v_month, pol.id);
    END IF;
  END IF;

  RETURN jsonb_build_object('ok',true,'tier1_earner',v_t1,'tier1_cents',v_g1,
                            'tier2_earner',v_t2,'tier2_cents',v_g2,'earning_month',v_month);
END; $$;

-- ── Fire the bounty when a paid membership is created ───────────────────────
CREATE OR REPLACE FUNCTION public.trg_referral_membership_bounty()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  IF NEW.status = 'active' THEN
    PERFORM public.referral_award_for_membership(NEW.id);
  END IF;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS referral_membership_bounty ON public.customer_memberships;
CREATE TRIGGER referral_membership_bounty
  AFTER INSERT ON public.customer_memberships
  FOR EACH ROW EXECUTE FUNCTION public.trg_referral_membership_bounty();

-- ── Turn OFF the per-order accrual (the switch to "instead of per-order"). ───
-- Existing already-credited/pending per-order rewards are left untouched; only
-- NEW per-order accrual stops. referral_process_order still runs its unlock step
-- harmlessly.
CREATE OR REPLACE FUNCTION public.referral_award_for_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE sql SECURITY DEFINER SET search_path = public
AS $$ SELECT jsonb_build_object('ok',false,'reason','per_order_rewards_disabled'); $$;

REVOKE ALL ON FUNCTION public._referral_grant_membership(uuid,uuid,uuid,smallint,int,date,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.referral_award_for_membership(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_award_for_membership(uuid) TO service_role;

NOTIFY pgrst, 'reload schema';
