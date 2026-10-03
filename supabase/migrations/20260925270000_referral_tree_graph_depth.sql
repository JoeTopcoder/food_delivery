-- Rank the diagram's direct branches by subtree DEPTH (then size), so the
-- deepest branches (which show all tiers) surface first within p_l1_limit.
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
  WITH RECURSIVE all_desc AS (
    SELECT a.purchaser_id AS id, a.purchaser_id AS branch, 1 AS lvl
    FROM referral_attributions a WHERE a.referrer_id = v_me AND a.effective_to IS NULL
    UNION ALL
    SELECT c.purchaser_id, ad.branch, ad.lvl + 1
    FROM referral_attributions c JOIN all_desc ad ON c.referrer_id = ad.id
    WHERE c.effective_to IS NULL AND ad.lvl < v_max
  ),
  l1 AS (
    SELECT branch AS id, max(lvl) AS depth, count(*) AS descendants
    FROM all_desc GROUP BY branch
    ORDER BY max(lvl) DESC, count(*) DESC
    LIMIT GREATEST(p_l1_limit,1)
  ),
  tree AS (
    SELECT l1.id AS node_id, v_me AS parent_id, 1 AS lvl FROM l1
    UNION ALL
    SELECT a.purchaser_id, a.referrer_id, t.lvl + 1
    FROM referral_attributions a JOIN tree t ON a.referrer_id = t.node_id
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
GRANT EXECUTE ON FUNCTION public.referral_tree_graph(int) TO authenticated;
NOTIFY pgrst, 'reload schema';
