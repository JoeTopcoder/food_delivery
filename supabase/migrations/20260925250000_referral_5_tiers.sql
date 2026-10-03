-- ============================================================================
-- HotBite Member Referral Rewards — extend from 2 tiers to 5.
-- Tier 1 (direct) = direct_reward_cents ($15). Tiers 2..max_tiers each pay
-- second_tier_reward_cents ($2.50). max_tiers is configurable (default 5).
-- ============================================================================

ALTER TABLE public.referral_reward_policies
  ADD COLUMN IF NOT EXISTS max_tiers int NOT NULL DEFAULT 5;
UPDATE public.referral_reward_policies SET max_tiers = 5 WHERE max_tiers < 5;

-- Allow tiers 1..10 in the ledger (constraint was IN (1,2)).
ALTER TABLE public.referral_rewards DROP CONSTRAINT IF EXISTS rr_tier_valid;
ALTER TABLE public.referral_rewards
  ADD CONSTRAINT rr_tier_valid CHECK (tier BETWEEN 1 AND 10);

-- Award: walk UP the referral chain from the purchaser, up to max_tiers levels.
-- Depth 1 = the purchaser's direct referrer ($15); depths 2..max = each further
-- ancestor ($2.50). Idempotent + per-earner monthly cap enforced by _referral_grant.
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
  v_value int; v_current uuid; v_earner uuid; v_amount int; v_depth int;
  v_tiers jsonb := '[]'::jsonb; v_granted int;
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

  IF NOT public.referral_member_active_at(o.user_id, v_ts)
     AND NOT public.is_hotbite_plus_member(o.user_id) THEN
    RETURN jsonb_build_object('ok',false,'reason','purchaser_not_member');
  END IF;

  v_month   := public.hotbite_month_key(v_ts);
  v_settle  := v_ts + make_interval(hours => pol.settlement_delay_hours);
  v_expires := ((v_month + interval '1 month')::timestamp
                 + make_interval(days => pol.carry_forward_days)) AT TIME ZONE 'America/Jamaica';
  v_value   := public.referral_order_final_value_cents(p_order_id);

  v_current := o.user_id;
  v_depth := 1;
  WHILE v_depth <= pol.max_tiers LOOP
    v_earner := public.referral_referrer_at(v_current, o.created_at);
    EXIT WHEN v_earner IS NULL;
    v_amount := CASE WHEN v_depth = 1 THEN pol.direct_reward_cents ELSE pol.second_tier_reward_cents END;
    v_granted := public._referral_grant(v_earner, o.user_id, p_order_id, v_depth::smallint,
                   v_amount, v_month, v_settle, v_expires, pol.id, v_value);
    v_tiers := v_tiers || jsonb_build_object('tier', v_depth, 'earner', v_earner, 'cents', v_granted);
    v_current := v_earner;
    v_depth := v_depth + 1;
  END LOOP;

  RETURN jsonb_build_object('ok', true, 'earning_month', v_month, 'tiers', v_tiers);
END;
$$;

-- Tree graph: recurse DOWN from the viewer up to max_tiers levels (was 2), for a
-- limited set of direct branches so the diagram stays legible.
CREATE OR REPLACE FUNCTION public.referral_tree_graph(p_l1_limit int DEFAULT 12)
RETURNS TABLE (
  node_id uuid, parent_id uuid, display_name text, level smallint,
  is_member boolean, qualifying_orders int, earned_cents int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_me uuid := auth.uid(); v_max int;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  v_max := COALESCE((public.referral_policy_current()).max_tiers, 5);
  RETURN QUERY
  WITH RECURSIVE l1 AS (
    SELECT a.purchaser_id AS id
    FROM referral_attributions a
    WHERE a.referrer_id = v_me AND a.effective_to IS NULL
    ORDER BY (SELECT count(*) FROM referral_attributions c WHERE c.referrer_id=a.purchaser_id AND c.effective_to IS NULL) DESC,
             a.created_at DESC
    LIMIT GREATEST(p_l1_limit,1)
  ),
  tree AS (
    SELECT l1.id AS node_id, v_me AS parent_id, 1 AS lvl FROM l1
    UNION ALL
    SELECT a.purchaser_id, a.referrer_id, t.lvl + 1
    FROM referral_attributions a
    JOIN tree t ON a.referrer_id = t.node_id
    WHERE a.effective_to IS NULL AND t.lvl < v_max
  )
  SELECT t.node_id, t.parent_id, public.referral_mask_name(u.name), t.lvl::smallint,
         public.is_hotbite_plus_member(t.node_id),
         (SELECT count(DISTINCT rr.source_order_id)::int FROM referral_rewards rr
            WHERE rr.earner_id=v_me AND rr.purchaser_id=t.node_id AND rr.status<>'reversed'),
         (SELECT COALESCE(sum(rr.reward_cents),0)::int FROM referral_rewards rr
            WHERE rr.earner_id=v_me AND rr.purchaser_id=t.node_id AND rr.status IN ('pending','credited'))
  FROM tree t JOIN users u ON u.id = t.node_id;
END;
$$;

REVOKE ALL ON FUNCTION public.referral_award_for_order(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_award_for_order(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.referral_tree_graph(int) TO authenticated;

NOTIFY pgrst, 'reload schema';
