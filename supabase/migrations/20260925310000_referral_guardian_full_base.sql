-- Fix the guardian maths: membership revenue must include the WHOLE active
-- paying-member base (every active member with price_paid > 0), not just members
-- who signed up this month. Referral payouts are the total committed (credited +
-- pending) to member wallets. Net = paying-base revenue − referral payouts.

CREATE OR REPLACE FUNCTION public.admin_referral_economics(p_from timestamptz, p_to timestamptz)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v jsonb; v_alert_pct numeric;
  v_rev bigint; v_credited bigint; v_pending bigint; v_committed bigint; v_members bigint;
BEGIN
  PERFORM public.require_admin();
  SELECT COALESCE(NULLIF(value,'')::numeric,60) INTO v_alert_pct FROM app_config WHERE key='referral_guardian_alert_pct';

  -- Whole active paying-member base.
  SELECT COALESCE(round(sum(price_paid)*100),0)::bigint, count(*)
    INTO v_rev, v_members
  FROM customer_memberships
  WHERE status='active' AND COALESCE(price_paid,0) > 0;

  -- Total referral rewards committed to wallets (paid + owed), excluding reversed.
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

CREATE OR REPLACE FUNCTION public.referral_guardian_daily()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_alert_pct numeric; v_rev bigint; v_committed bigint; v_credited bigint; v_pending bigint; v_members bigint;
  v_verdict text; a record; v_title text; v_body text; v_key text; v_payload jsonb;
BEGIN
  SELECT COALESCE(NULLIF(value,'')::numeric,60) INTO v_alert_pct FROM app_config WHERE key='referral_guardian_alert_pct';

  SELECT COALESCE(round(sum(price_paid)*100),0)::bigint, count(*) INTO v_rev, v_members
  FROM customer_memberships WHERE status='active' AND COALESCE(price_paid,0)>0;

  SELECT COALESCE(sum(reward_cents) FILTER (WHERE status='credited'),0)::bigint,
         COALESCE(sum(reward_cents) FILTER (WHERE status='pending'),0)::bigint
    INTO v_credited, v_pending FROM referral_rewards;
  v_committed := v_credited + v_pending;

  v_verdict := CASE
    WHEN v_rev - v_committed < 0 THEN 'ALERT'
    WHEN v_rev>0 AND 100.0*v_committed/v_rev > v_alert_pct THEN 'WATCH'
    ELSE 'OK' END;

  v_title := 'Membership referral — '||v_verdict;
  v_body := format('%s active paying members · membership revenue %s · referral payouts %s (paid %s + %s pending) · net %s',
    v_members, '$'||to_char(v_rev/100.0,'FM999999990.00'), '$'||to_char(v_committed/100.0,'FM999999990.00'),
    '$'||to_char(v_credited/100.0,'FM999999990.00'), '$'||to_char(v_pending/100.0,'FM999999990.00'),
    '$'||to_char((v_rev-v_committed)/100.0,'FM999999990.00'));

  v_payload := jsonb_build_object('verdict',v_verdict,'paying_members',v_members,
    'membership_revenue_cents',v_rev,'referral_paid_cents',v_credited,
    'referral_pending_cents',v_pending,'net_cents',v_rev-v_committed);

  FOR a IN SELECT id FROM users WHERE role='admin' LOOP
    IF NOT EXISTS (SELECT 1 FROM notifications n WHERE n.user_id=a.id AND n.type='referral_guardian'
                   AND (n.created_at AT TIME ZONE 'America/Jamaica')::date = (now() AT TIME ZONE 'America/Jamaica')::date) THEN
      INSERT INTO notifications(user_id, title, body, type, data)
      VALUES (a.id, v_title, v_body, 'referral_guardian', v_payload);
    END IF;
  END LOOP;

  SELECT value INTO v_key FROM app_config WHERE key='automation_service_key';
  IF v_key IS NOT NULL THEN
    BEGIN
      PERFORM extensions.http_post(
        url := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/referral-guardian-email',
        body := v_payload::text,
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key));
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;

  RETURN jsonb_build_object('verdict',v_verdict,'metrics',v_payload);
END;
$$;
REVOKE ALL ON FUNCTION public.referral_guardian_daily() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_guardian_daily() TO service_role;

NOTIFY pgrst, 'reload schema';
