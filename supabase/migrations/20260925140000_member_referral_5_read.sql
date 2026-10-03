-- ============================================================================
-- HotBite Member Referral Rewards — 5/5 : read RPCs (customer + admin)
-- ----------------------------------------------------------------------------
-- Customer RPCs expose ONLY the viewer's own programme data. Referred customers'
-- order contents, spend, address, phone and payment info are never returned —
-- only counts and the viewer's own earned amounts. Two earning levels only.
-- ============================================================================

-- Privacy-safe display name: first name + last initial (never email).
CREATE OR REPLACE FUNCTION public.referral_mask_name(p_name text)
RETURNS text
LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
    WHEN p_name IS NULL OR btrim(p_name) = '' THEN 'HotBite Member'
    WHEN position(' ' in btrim(p_name)) = 0 THEN btrim(p_name)
    ELSE split_part(btrim(p_name),' ',1) || ' ' ||
         upper(left(split_part(btrim(p_name),' ',2),1)) || '.'
  END;
$$;

-- Programme summary for the current user.
CREATE OR REPLACE FUNCTION public.referral_my_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  pol referral_reward_policies%ROWTYPE;
  v_month date := public.hotbite_month_key(now());
  v_code text; v_direct int; v_direct_active int; v_second int; v_second_active int;
  v_personal int; v_cap_used int; v_pending int; v_credited int; v_expiring int;
  v_t1_pending int; v_t2_pending int; v_t1_credited int; v_t2_credited int;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  pol := public.referral_policy_current();
  SELECT referral_code INTO v_code FROM users WHERE id = v_me;

  SELECT count(*), count(*) FILTER (WHERE public.is_hotbite_plus_member(a.purchaser_id))
    INTO v_direct, v_direct_active
  FROM referral_attributions a WHERE a.referrer_id = v_me AND a.effective_to IS NULL;

  SELECT count(*), count(*) FILTER (WHERE public.is_hotbite_plus_member(a2.purchaser_id))
    INTO v_second, v_second_active
  FROM referral_attributions a2
  WHERE a2.effective_to IS NULL
    AND a2.referrer_id IN (SELECT purchaser_id FROM referral_attributions
                           WHERE referrer_id = v_me AND effective_to IS NULL);

  v_personal := public.referral_personal_qualifying_count(v_me, v_month);
  SELECT COALESCE(earned_cents,0) INTO v_cap_used FROM referral_cap_usage
    WHERE earner_id = v_me AND earning_month = v_month;

  SELECT COALESCE(sum(reward_cents) FILTER (WHERE status='pending'),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='credited'),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='pending' AND tier=1),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='pending' AND tier=2),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='credited' AND tier=1),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='credited' AND tier=2),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='pending' AND expires_at < now() + interval '14 days'),0)
    INTO v_pending, v_credited, v_t1_pending, v_t2_pending, v_t1_credited, v_t2_credited, v_expiring
  FROM referral_rewards WHERE earner_id = v_me;

  RETURN jsonb_build_object(
    'referral_code', v_code,
    'direct_reward_cents', pol.direct_reward_cents,
    'second_tier_reward_cents', pol.second_tier_reward_cents,
    'monthly_cap_cents', pol.monthly_cap_cents,
    'personal_orders_required', pol.personal_orders_required,
    'enabled', pol.enabled,
    'direct_count', v_direct, 'direct_active_members', v_direct_active,
    'second_tier_count', v_second, 'second_tier_active_members', v_second_active,
    'personal_orders_this_month', v_personal,
    'unlocked', v_personal >= pol.personal_orders_required,
    'cap_used_cents', COALESCE(v_cap_used,0),
    'pending_cents', v_pending, 'credited_cents', v_credited,
    'tier1_pending_cents', v_t1_pending, 'tier2_pending_cents', v_t2_pending,
    'tier1_credited_cents', v_t1_credited, 'tier2_credited_cents', v_t2_credited,
    'expiring_soon_cents', v_expiring,
    'earning_month', v_month
  );
END;
$$;

-- Two-level tree. p_parent NULL → my direct referrals (level 1). p_parent = one
-- of my direct referrals → that account's referrals (level 2). Deeper is refused
-- (Joel never sees David's referrals). Returns counts + the viewer's earned
-- amount only — never the referred customer's private data.
CREATE OR REPLACE FUNCTION public.referral_my_tree(
  p_parent uuid DEFAULT NULL,
  p_filter text DEFAULT 'all',
  p_limit  int DEFAULT 25,
  p_offset int DEFAULT 0)
RETURNS TABLE (
  referred_id      uuid,
  display_name     text,
  joined_at        timestamptz,
  is_member        boolean,
  level            smallint,
  qualifying_orders int,
  earned_cents     int,
  child_count      int
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_me uuid := auth.uid(); v_level smallint;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;

  IF p_parent IS NULL THEN
    v_level := 1;
    p_parent := v_me;
  ELSE
    -- p_parent must be a DIRECT referral of the viewer → its children are level 2.
    IF NOT EXISTS (SELECT 1 FROM referral_attributions
                   WHERE referrer_id = v_me AND purchaser_id = p_parent AND effective_to IS NULL) THEN
      RAISE EXCEPTION 'Not allowed to view this branch' USING ERRCODE='42501';
    END IF;
    v_level := 2;
  END IF;

  RETURN QUERY
  SELECT u.id,
         public.referral_mask_name(u.name),
         u.created_at,
         public.is_hotbite_plus_member(u.id),
         v_level,
         (SELECT count(DISTINCT rr.source_order_id)::int FROM referral_rewards rr
            WHERE rr.earner_id = v_me AND rr.purchaser_id = u.id AND rr.status <> 'reversed'),
         (SELECT COALESCE(sum(rr.reward_cents),0)::int FROM referral_rewards rr
            WHERE rr.earner_id = v_me AND rr.purchaser_id = u.id AND rr.status IN ('pending','credited')),
         CASE WHEN v_level = 1
              THEN (SELECT count(*)::int FROM referral_attributions c
                    WHERE c.referrer_id = u.id AND c.effective_to IS NULL)
              ELSE 0 END
  FROM referral_attributions a
  JOIN users u ON u.id = a.purchaser_id
  WHERE a.referrer_id = p_parent AND a.effective_to IS NULL
    AND (p_filter = 'all'
      OR (p_filter = 'active' AND public.is_hotbite_plus_member(u.id))
      OR (p_filter = 'not_member' AND NOT public.is_hotbite_plus_member(u.id))
      OR (p_filter = 'has_orders' AND EXISTS (SELECT 1 FROM referral_rewards rr
             WHERE rr.earner_id = v_me AND rr.purchaser_id = u.id AND rr.status <> 'reversed')))
  ORDER BY u.created_at DESC
  LIMIT LEAST(GREATEST(p_limit,1),100) OFFSET GREATEST(p_offset,0);
END;
$$;

-- Itemized reward history for the current user.
CREATE OR REPLACE FUNCTION public.referral_my_rewards(p_limit int DEFAULT 50, p_offset int DEFAULT 0)
RETURNS TABLE (
  id uuid, tier smallint, reward_cents int, status text, earning_month date,
  created_at timestamptz, credited_at timestamptz, expires_at timestamptz,
  purchaser_name text, reason text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT rr.id, rr.tier, rr.reward_cents, rr.status, rr.earning_month,
         rr.created_at, rr.credited_at, rr.expires_at,
         public.referral_mask_name(u.name), rr.reason
  FROM referral_rewards rr
  JOIN users u ON u.id = rr.purchaser_id
  WHERE rr.earner_id = auth.uid()
  ORDER BY rr.created_at DESC
  LIMIT LEAST(GREATEST(p_limit,1),200) OFFSET GREATEST(p_offset,0);
$$;

-- Admin: programme totals over a window (by reward created_at).
CREATE OR REPLACE FUNCTION public.admin_referral_overview(p_from timestamptz, p_to timestamptz)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public.require_admin();
  SELECT jsonb_build_object(
    'tier1_orders', count(*) FILTER (WHERE tier=1 AND status<>'reversed'),
    'tier2_orders', count(*) FILTER (WHERE tier=2 AND status<>'reversed'),
    'pending_cents', COALESCE(sum(reward_cents) FILTER (WHERE status='pending'),0),
    'credited_cents', COALESCE(sum(reward_cents) FILTER (WHERE status='credited'),0),
    'expired_cents', COALESCE(sum(reward_cents) FILTER (WHERE status='expired'),0),
    'reversed_cents', COALESCE(sum(reward_cents) FILTER (WHERE status='reversed'),0),
    'tier1_cents', COALESCE(sum(reward_cents) FILTER (WHERE tier=1 AND status IN ('pending','credited')),0),
    'tier2_cents', COALESCE(sum(reward_cents) FILTER (WHERE tier=2 AND status IN ('pending','credited')),0),
    'total_referral_cost_cents', COALESCE(sum(reward_cents) FILTER (WHERE status IN ('pending','credited')),0),
    'earning_accounts', count(DISTINCT earner_id) FILTER (WHERE status IN ('pending','credited'))
  ) INTO v
  FROM referral_rewards
  WHERE created_at >= p_from AND created_at < p_to;
  RETURN v;
END;
$$;

-- Admin: auditable manual reward adjustment straight to a member's wallet.
CREATE OR REPLACE FUNCTION public.admin_referral_adjust(
  p_earner uuid, p_amount_cents int, p_reason text)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_admin uuid; v_txn uuid;
BEGIN
  v_admin := public.require_admin();
  IF p_amount_cents = 0 THEN RAISE EXCEPTION 'amount must be non-zero'; END IF;
  INSERT INTO wallets(user_id,balance,cashback_balance) VALUES (p_earner,0,0)
    ON CONFLICT (user_id) DO NOTHING;
  UPDATE wallets SET balance = COALESCE(balance,0) + (p_amount_cents/100.0), updated_at=now()
    WHERE user_id = p_earner;
  INSERT INTO wallet_transactions(user_id, amount, type, payment_method, status, description)
    VALUES (p_earner, (p_amount_cents/100.0),
            CASE WHEN p_amount_cents > 0 THEN 'cashback' ELSE 'penalty' END,
            'wallet', 'completed', 'Referral manual adjustment: '||COALESCE(p_reason,''))
    RETURNING id INTO v_txn;
  RETURN jsonb_build_object('ok',true,'wallet_txn',v_txn,'by_admin',v_admin);
END;
$$;

GRANT EXECUTE ON FUNCTION public.referral_my_summary() TO authenticated;
GRANT EXECUTE ON FUNCTION public.referral_my_tree(uuid,text,int,int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.referral_my_rewards(int,int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_referral_overview(timestamptz,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_referral_adjust(uuid,int,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.referral_mask_name(text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
