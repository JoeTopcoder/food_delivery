-- Referral tree as a graph for the visual pyramid diagram: the viewer's direct
-- (level 1) referrals and their referrals (level 2), in one call, with parent
-- linkage. Privacy-masked; two earning levels only. p_l1_limit caps how many
-- L1 branches are drawn so the diagram stays legible on a phone.
CREATE OR REPLACE FUNCTION public.referral_tree_graph(p_l1_limit int DEFAULT 12)
RETURNS TABLE (
  node_id      uuid,
  parent_id    uuid,
  display_name text,
  level        smallint,
  is_member    boolean,
  qualifying_orders int,
  earned_cents int
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_me uuid := auth.uid();
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  RETURN QUERY
  WITH l1 AS (
    SELECT a.purchaser_id AS id
    FROM referral_attributions a
    WHERE a.referrer_id = v_me AND a.effective_to IS NULL
    ORDER BY (SELECT count(*) FROM referral_attributions c WHERE c.referrer_id=a.purchaser_id AND c.effective_to IS NULL) DESC,
             a.created_at DESC
    LIMIT GREATEST(p_l1_limit,1)
  ),
  nodes AS (
    SELECT u.id AS node_id, v_me AS parent_id, u.name, 1::smallint AS lvl FROM l1 JOIN users u ON u.id=l1.id
    UNION ALL
    SELECT u.id, a.referrer_id, u.name, 2::smallint
    FROM referral_attributions a
    JOIN l1 ON l1.id = a.referrer_id
    JOIN users u ON u.id = a.purchaser_id
    WHERE a.effective_to IS NULL
  )
  SELECT n.node_id, n.parent_id, public.referral_mask_name(n.name), n.lvl,
         public.is_hotbite_plus_member(n.node_id),
         (SELECT count(DISTINCT rr.source_order_id)::int FROM referral_rewards rr
            WHERE rr.earner_id=v_me AND rr.purchaser_id=n.node_id AND rr.status<>'reversed'),
         (SELECT COALESCE(sum(rr.reward_cents),0)::int FROM referral_rewards rr
            WHERE rr.earner_id=v_me AND rr.purchaser_id=n.node_id AND rr.status IN ('pending','credited'))
  FROM nodes n;
END;
$$;
GRANT EXECUTE ON FUNCTION public.referral_tree_graph(int) TO authenticated;
NOTIFY pgrst, 'reload schema';
