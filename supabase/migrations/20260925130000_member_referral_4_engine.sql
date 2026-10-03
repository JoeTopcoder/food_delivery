-- ============================================================================
-- HotBite Member Referral Rewards — 4/5 : reward engine
-- ----------------------------------------------------------------------------
-- award  → creates pending tier-1/tier-2 rewards for a qualifying order, with
--          atomic per-(earner, month) cap enforcement.
-- unlock → once an earner completes 3 personal qualifying orders in a Jamaica
--          month (and has an active membership), moves their eligible pending
--          rewards into the HotBite wallet.
-- reverse→ on refund/adjustment, reverses that order's rewards (clawing back the
--          wallet safely) and decrements cap usage.
-- expire → cron: retires pending rewards past their carry-forward life.
-- All are idempotent and safe under retries / concurrent completions.
-- ============================================================================

-- Was the account an active paid member at instant p_ts?
CREATE OR REPLACE FUNCTION public.referral_member_active_at(p_user uuid, p_ts timestamptz)
RETURNS boolean
LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM customer_memberships m
    WHERE m.user_id = p_user
      AND m.status = 'active'
      AND m.start_date <= p_ts
      AND (m.end_date IS NULL OR m.end_date >= p_ts)
  );
$$;

-- Grant one reward row (idempotent) with atomic cap enforcement. Returns the
-- cents actually granted (0 if the monthly cap is already reached or duplicate).
CREATE OR REPLACE FUNCTION public._referral_grant(
  p_earner uuid, p_purchaser uuid, p_order uuid, p_tier smallint,
  p_amount int, p_month date, p_settle timestamptz, p_expires timestamptz,
  p_policy uuid, p_order_value int)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_used int; v_cap int; v_remaining int; v_grant int; v_reason text;
BEGIN
  IF p_earner IS NULL OR p_earner = p_purchaser THEN
    -- self (same account) never earns from its own order
    RETURN 0;
  END IF;
  -- Already awarded for this (order, earner, tier)? Idempotent no-op.
  IF EXISTS (SELECT 1 FROM referral_rewards
             WHERE source_order_id = p_order AND earner_id = p_earner AND tier = p_tier) THEN
    RETURN 0;
  END IF;

  v_cap := (public.referral_policy_at(p_settle)).monthly_cap_cents;

  -- Lock (or create) the earner's cap-usage row for the month.
  INSERT INTO referral_cap_usage(earner_id, earning_month, earned_cents)
  VALUES (p_earner, p_month, 0)
  ON CONFLICT (earner_id, earning_month) DO NOTHING;

  SELECT earned_cents INTO v_used FROM referral_cap_usage
  WHERE earner_id = p_earner AND earning_month = p_month FOR UPDATE;

  v_remaining := GREATEST(0, v_cap - COALESCE(v_used,0));
  v_grant := LEAST(p_amount, v_remaining);
  v_reason := CASE WHEN v_grant < p_amount THEN 'tier'||p_tier||'_capped' ELSE 'tier'||p_tier END;

  INSERT INTO referral_rewards(
    earner_id, purchaser_id, source_order_id, tier, reward_cents, status,
    earning_month, policy_id, order_value_cents, settle_at, expires_at, reason)
  VALUES (p_earner, p_purchaser, p_order, p_tier, v_grant, 'pending',
          p_month, p_policy, p_order_value, p_settle, p_expires, v_reason)
  ON CONFLICT (source_order_id, earner_id, tier) DO NOTHING;

  IF v_grant > 0 THEN
    UPDATE referral_cap_usage SET earned_cents = earned_cents + v_grant, updated_at = now()
    WHERE earner_id = p_earner AND earning_month = p_month;
  END IF;
  RETURN v_grant;
END;
$$;

-- Award rewards for a qualifying order (idempotent).
CREATE OR REPLACE FUNCTION public.referral_award_for_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o orders%ROWTYPE;
  pol referral_reward_policies%ROWTYPE;
  v_ts timestamptz; v_month date; v_settle timestamptz; v_expires timestamptz;
  v_value int; v_t1 uuid; v_t2 uuid; v_g1 int := 0; v_g2 int := 0;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','order_not_found'); END IF;
  IF NOT public.referral_order_qualifies(p_order_id) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_qualifying');
  END IF;

  v_ts := COALESCE(o.delivered_at, o.created_at);
  pol := public.referral_policy_at(v_ts);
  IF pol.id IS NULL OR NOT pol.enabled THEN
    RETURN jsonb_build_object('ok',false,'reason','programme_disabled');
  END IF;

  -- Purchaser must be an active paid member for the order to generate rewards.
  IF NOT public.referral_member_active_at(o.user_id, v_ts)
     AND NOT public.is_hotbite_plus_member(o.user_id) THEN
    RETURN jsonb_build_object('ok',false,'reason','purchaser_not_member');
  END IF;

  v_month   := public.hotbite_month_key(v_ts);
  v_settle  := v_ts + make_interval(hours => pol.settlement_delay_hours);
  v_expires := ((v_month + interval '1 month')::timestamp
                 + make_interval(days => pol.carry_forward_days)) AT TIME ZONE 'America/Jamaica';
  v_value   := public.referral_order_final_value_cents(p_order_id);

  -- Tier 1: purchaser's referrer at order-placement time.
  v_t1 := public.referral_referrer_at(o.user_id, o.created_at);
  IF v_t1 IS NOT NULL THEN
    v_g1 := public._referral_grant(v_t1, o.user_id, p_order_id, 1::smallint,
              pol.direct_reward_cents, v_month, v_settle, v_expires, pol.id, v_value);
    -- Tier 2: that referrer's own referrer (second tier only; never tier 3).
    v_t2 := public.referral_referrer_at(v_t1, o.created_at);
    IF v_t2 IS NOT NULL THEN
      v_g2 := public._referral_grant(v_t2, o.user_id, p_order_id, 2::smallint,
                pol.second_tier_reward_cents, v_month, v_settle, v_expires, pol.id, v_value);
    END IF;
  END IF;

  RETURN jsonb_build_object('ok',true,'tier1_earner',v_t1,'tier1_cents',v_g1,
                            'tier2_earner',v_t2,'tier2_cents',v_g2,'earning_month',v_month);
END;
$$;

-- Move an earner's eligible pending rewards into their wallet.
CREATE OR REPLACE FUNCTION public.referral_unlock_rewards(p_earner uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pol referral_reward_policies%ROWTYPE;
  v_required int; r record; v_credited int := 0; v_count int := 0; v_txn uuid;
BEGIN
  pol := public.referral_policy_current();
  v_required := COALESCE(pol.personal_orders_required, 3);

  -- Earner must currently hold an active membership to unlock.
  IF NOT public.is_hotbite_plus_member(p_earner) THEN
    RETURN jsonb_build_object('ok',false,'reason','earner_not_member');
  END IF;

  -- Months in which the earner met the personal-order threshold.
  CREATE TEMP TABLE _unlock_months ON COMMIT DROP AS
  SELECT DISTINCT public.hotbite_month_key(COALESCE(o.delivered_at,o.created_at)) AS m
  FROM orders o
  WHERE o.user_id = p_earner AND o.status='delivered'
  GROUP BY 1
  HAVING count(*) FILTER (WHERE public.referral_order_qualifies(o.id)) >= v_required;

  -- Credit each pending, settled, non-expired reward whose earning month is
  -- at/before some unlock month. Lock rows to stay concurrency-safe.
  FOR r IN
    SELECT rr.* FROM referral_rewards rr
    WHERE rr.earner_id = p_earner
      AND rr.status = 'pending'
      AND rr.settle_at <= now()
      AND rr.expires_at > now()
      AND rr.reward_cents > 0
      AND EXISTS (SELECT 1 FROM _unlock_months um WHERE um.m >= rr.earning_month)
    ORDER BY rr.created_at
    FOR UPDATE
  LOOP
    -- Credit wallet ('cashback') + balance in one transaction.
    INSERT INTO wallets(user_id, balance, cashback_balance)
      VALUES (p_earner, 0, 0) ON CONFLICT (user_id) DO NOTHING;
    UPDATE wallets SET balance = COALESCE(balance,0) + (r.reward_cents/100.0),
                       updated_at = now()
      WHERE user_id = p_earner;
    INSERT INTO wallet_transactions(user_id, amount, type, payment_method, status, order_id, description)
      VALUES (p_earner, (r.reward_cents/100.0), 'cashback', 'wallet', 'completed', r.source_order_id,
              'Referral reward (tier '||r.tier||')')
      RETURNING id INTO v_txn;
    UPDATE referral_rewards
       SET status='credited', credited_at=now(), wallet_txn_id=v_txn
     WHERE id = r.id;
    v_credited := v_credited + r.reward_cents;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('ok',true,'credited_count',v_count,'credited_cents',v_credited);
END;
$$;

-- Reverse an order's rewards on refund/adjustment (idempotent, safe clawback).
CREATE OR REPLACE FUNCTION public.referral_reverse_order(p_order_id uuid, p_reason text DEFAULT 'refund')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r record; v_reversed int := 0; v_clawed int := 0;
BEGIN
  FOR r IN
    SELECT * FROM referral_rewards
    WHERE source_order_id = p_order_id AND status IN ('pending','credited')
    FOR UPDATE
  LOOP
    IF r.status = 'credited' AND r.reward_cents > 0 THEN
      -- Claw back from the wallet (balance may go negative = clawback owed).
      UPDATE wallets SET balance = COALESCE(balance,0) - (r.reward_cents/100.0), updated_at=now()
        WHERE user_id = r.earner_id;
      INSERT INTO wallet_transactions(user_id, amount, type, payment_method, status, order_id, description)
        VALUES (r.earner_id, -(r.reward_cents/100.0), 'penalty', 'wallet', 'completed', r.source_order_id,
                'Referral reward reversal ('||p_reason||')');
      v_clawed := v_clawed + r.reward_cents;
    END IF;
    -- Free the cap usage this reward consumed.
    IF r.reward_cents > 0 THEN
      UPDATE referral_cap_usage
         SET earned_cents = GREATEST(0, earned_cents - r.reward_cents), updated_at=now()
       WHERE earner_id = r.earner_id AND earning_month = r.earning_month;
    END IF;
    UPDATE referral_rewards SET status='reversed', reversed_at=now(),
           reason = COALESCE(reason,'')||' | reversed:'||p_reason
     WHERE id = r.id;
    v_reversed := v_reversed + 1;
  END LOOP;
  RETURN jsonb_build_object('ok',true,'reversed_count',v_reversed,'clawed_back_cents',v_clawed);
END;
$$;

-- Cron: expire pending rewards past their carry-forward life.
CREATE OR REPLACE FUNCTION public.referral_expire_pending()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE r record; v_n int := 0;
BEGIN
  FOR r IN SELECT * FROM referral_rewards
           WHERE status='pending' AND expires_at <= now() FOR UPDATE
  LOOP
    IF r.reward_cents > 0 THEN
      UPDATE referral_cap_usage
         SET earned_cents = GREATEST(0, earned_cents - r.reward_cents), updated_at=now()
       WHERE earner_id = r.earner_id AND earning_month = r.earning_month;
    END IF;
    UPDATE referral_rewards SET status='expired' WHERE id = r.id;
    v_n := v_n + 1;
  END LOOP;
  RETURN jsonb_build_object('ok',true,'expired_count',v_n);
END;
$$;

-- Orchestrator called on order completion: award for this order, then try to
-- unlock the purchaser's own pending rewards (their order may complete the 3).
CREATE OR REPLACE FUNCTION public.referral_process_order(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE o orders%ROWTYPE; v_award jsonb; v_unlock jsonb;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','order_not_found'); END IF;
  v_award := public.referral_award_for_order(p_order_id);
  BEGIN
    v_unlock := public.referral_unlock_rewards(o.user_id);
  EXCEPTION WHEN OTHERS THEN
    v_unlock := jsonb_build_object('ok',false,'reason',SQLERRM);
  END;
  RETURN jsonb_build_object('award',v_award,'unlock',v_unlock);
END;
$$;

REVOKE ALL ON FUNCTION public._referral_grant(uuid,uuid,uuid,smallint,int,date,timestamptz,timestamptz,uuid,int) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.referral_award_for_order(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.referral_reverse_order(uuid,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.referral_expire_pending() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.referral_process_order(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_award_for_order(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.referral_reverse_order(uuid,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.referral_expire_pending() TO service_role;
GRANT EXECUTE ON FUNCTION public.referral_process_order(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.referral_unlock_rewards(uuid) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_member_active_at(uuid,timestamptz) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
