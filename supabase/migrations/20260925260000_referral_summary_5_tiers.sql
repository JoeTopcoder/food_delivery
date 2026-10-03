-- Update the customer summary for the 5-tier model: "second tier" figures now
-- aggregate tiers 2..max, and the network count covers the whole downline within
-- max_tiers levels (not just level 2).
CREATE OR REPLACE FUNCTION public.referral_my_summary()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_me uuid := auth.uid();
  pol referral_reward_policies%ROWTYPE;
  v_month date := public.hotbite_month_key(now());
  v_code text; v_direct int; v_direct_active int; v_net int; v_net_active int;
  v_personal int; v_cap_used int; v_pending int; v_credited int; v_expiring int;
  v_t1_pending int; v_t2_pending int; v_t1_credited int; v_t2_credited int; v_max int;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  pol := public.referral_policy_current();
  v_max := COALESCE(pol.max_tiers, 5);
  SELECT referral_code INTO v_code FROM users WHERE id = v_me;

  SELECT count(*), count(*) FILTER (WHERE public.is_hotbite_plus_member(a.purchaser_id))
    INTO v_direct, v_direct_active
  FROM referral_attributions a WHERE a.referrer_id = v_me AND a.effective_to IS NULL;

  -- Whole downline in tiers 2..max_tiers (recursive).
  WITH RECURSIVE dl AS (
    SELECT a.purchaser_id AS id, 1 AS lvl
    FROM referral_attributions a WHERE a.referrer_id = v_me AND a.effective_to IS NULL
    UNION ALL
    SELECT a.purchaser_id, dl.lvl + 1
    FROM referral_attributions a JOIN dl ON a.referrer_id = dl.id
    WHERE a.effective_to IS NULL AND dl.lvl < v_max
  )
  SELECT count(*) FILTER (WHERE lvl >= 2),
         count(*) FILTER (WHERE lvl >= 2 AND public.is_hotbite_plus_member(id))
    INTO v_net, v_net_active FROM dl;

  v_personal := public.referral_personal_qualifying_count(v_me, v_month);
  SELECT COALESCE(earned_cents,0) INTO v_cap_used FROM referral_cap_usage
    WHERE earner_id = v_me AND earning_month = v_month;

  SELECT COALESCE(sum(reward_cents) FILTER (WHERE status='pending'),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='credited'),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='pending' AND tier=1),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='pending' AND tier>=2),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='credited' AND tier=1),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='credited' AND tier>=2),0),
         COALESCE(sum(reward_cents) FILTER (WHERE status='pending' AND expires_at < now() + interval '14 days'),0)
    INTO v_pending, v_credited, v_t1_pending, v_t2_pending, v_t1_credited, v_t2_credited, v_expiring
  FROM referral_rewards WHERE earner_id = v_me;

  RETURN jsonb_build_object(
    'referral_code', v_code,
    'direct_reward_cents', pol.direct_reward_cents,
    'second_tier_reward_cents', pol.second_tier_reward_cents,
    'max_tiers', v_max,
    'monthly_cap_cents', pol.monthly_cap_cents,
    'personal_orders_required', pol.personal_orders_required,
    'enabled', pol.enabled,
    'direct_count', v_direct, 'direct_active_members', v_direct_active,
    'second_tier_count', v_net, 'second_tier_active_members', v_net_active,
    'personal_orders_this_month', v_personal,
    'unlocked', v_personal >= pol.personal_orders_required,
    'cap_used_cents', COALESCE(v_cap_used,0),
    'pending_cents', v_pending, 'credited_cents', v_credited,
    'tier1_pending_cents', v_t1_pending, 'tier2_pending_cents', v_t2_pending,
    'tier1_credited_cents', v_t1_credited, 'tier2_credited_cents', v_t2_credited,
    'expiring_soon_cents', v_expiring, 'earning_month', v_month);
END;
$$;
GRANT EXECUTE ON FUNCTION public.referral_my_summary() TO authenticated;
NOTIFY pgrst, 'reload schema';
