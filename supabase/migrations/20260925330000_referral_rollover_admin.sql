-- Admin setter for the cap-rollover %, and expose it on the economics read.
CREATE OR REPLACE FUNCTION public.admin_set_referral_rollover_pct(p_pct numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_admin uuid;
BEGIN
  v_admin := public.require_admin();
  IF p_pct IS NULL OR p_pct < 0 OR p_pct > 100 THEN RAISE EXCEPTION 'rollover pct must be 0-100'; END IF;
  INSERT INTO app_config(key,value) VALUES ('referral_cap_rollover_pct', p_pct::text)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  RETURN jsonb_build_object('ok',true,'referral_cap_rollover_pct',p_pct);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_referral_rollover_pct(numeric) TO authenticated;

-- Add rollover_pct + monthly_cap to the economics jsonb (append, keep everything else).
CREATE OR REPLACE FUNCTION public.admin_referral_economics(p_from timestamptz, p_to timestamptz)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v jsonb; v_alert_pct numeric; v_roll numeric;
  v_rev bigint; v_credited bigint; v_pending bigint; v_committed bigint; v_members bigint;
BEGIN
  PERFORM public.require_admin();
  SELECT COALESCE(NULLIF(value,'')::numeric,60) INTO v_alert_pct FROM app_config WHERE key='referral_guardian_alert_pct';
  SELECT COALESCE(NULLIF(value,'')::numeric,50) INTO v_roll FROM app_config WHERE key='referral_cap_rollover_pct';

  SELECT COALESCE(round(sum(price_paid)*100),0)::bigint, count(*)
    INTO v_rev, v_members
  FROM customer_memberships WHERE status='active' AND COALESCE(price_paid,0) > 0;

  SELECT COALESCE(sum(reward_cents) FILTER (WHERE status='credited'),0)::bigint,
         COALESCE(sum(reward_cents) FILTER (WHERE status='pending'),0)::bigint
    INTO v_credited, v_pending FROM referral_rewards;
  v_committed := v_credited + v_pending;

  v := jsonb_build_object(
    'paying_members', v_members,
    'membership_revenue_cents', v_rev,
    'referral_paid_to_wallet_cents', v_credited,
    'referral_pending_cents', v_pending,
    'referral_committed_cents', v_committed,
    'net_contribution_cents', v_rev - v_committed,
    'payout_to_revenue_pct', CASE WHEN v_rev>0 THEN round(100.0*v_committed/v_rev,1) ELSE NULL END,
    'alert_threshold_pct', v_alert_pct,
    'cap_rollover_pct', v_roll,
    'monthly_cap_cents', (public.referral_policy_current()).monthly_cap_cents,
    'verdict', CASE
        WHEN v_rev - v_committed < 0 THEN 'alert_losing'
        WHEN v_rev>0 AND 100.0*v_committed/v_rev > v_alert_pct THEN 'watch'
        ELSE 'healthy' END,
    'top_earners', COALESCE((
      SELECT jsonb_agg(t) FROM (
        SELECT public.referral_mask_name(u.name) AS earner, sum(rr.reward_cents) AS cents,
               count(DISTINCT rr.source_order_id) AS orders
        FROM referral_rewards rr JOIN users u ON u.id=rr.earner_id
        WHERE rr.status IN ('pending','credited') AND rr.created_at>=p_from AND rr.created_at<p_to
        GROUP BY rr.earner_id, u.name ORDER BY sum(rr.reward_cents) DESC LIMIT 5) t), '[]'::jsonb));
  RETURN v;
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_referral_economics(timestamptz,timestamptz) TO authenticated;
NOTIFY pgrst, 'reload schema';
