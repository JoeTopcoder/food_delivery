-- Add email delivery to the daily membership-referral guardian, and an admin
-- setter for the alert threshold.

CREATE OR REPLACE FUNCTION public.referral_guardian_daily()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_from timestamptz; v_alert_pct numeric;
  v_rev bigint; v_committed bigint; v_credited bigint; v_pending bigint; v_members bigint;
  v_verdict text; a record; v_title text; v_body text; v_key text; v_payload jsonb;
BEGIN
  v_from := (date_trunc('month', now() AT TIME ZONE 'America/Jamaica')) AT TIME ZONE 'America/Jamaica';
  SELECT COALESCE(NULLIF(value,'')::numeric,60) INTO v_alert_pct FROM app_config WHERE key='referral_guardian_alert_pct';

  SELECT COALESCE(round(sum(price_paid)*100),0)::bigint, count(*) INTO v_rev, v_members
  FROM customer_memberships WHERE COALESCE(price_paid,0)>0 AND start_date>=v_from AND start_date<now();

  SELECT COALESCE(sum(reward_cents) FILTER (WHERE status='credited' AND credited_at>=v_from),0)::bigint,
         COALESCE(sum(reward_cents) FILTER (WHERE status='pending' AND created_at>=v_from),0)::bigint
    INTO v_credited, v_pending FROM referral_rewards;
  v_committed := v_credited + v_pending;

  v_verdict := CASE
    WHEN v_rev - v_committed < 0 THEN 'ALERT'
    WHEN v_rev>0 AND 100.0*v_committed/v_rev > v_alert_pct THEN 'WATCH'
    ELSE 'OK' END;

  v_title := 'Membership referral — '||v_verdict;
  v_body := format('Month to date: %s paying members · membership revenue %s · referral paid to wallet %s (+%s pending) · net %s',
    v_members, '$'||to_char(v_rev/100.0,'FM999999990.00'), '$'||to_char(v_credited/100.0,'FM999999990.00'),
    '$'||to_char(v_pending/100.0,'FM999999990.00'), '$'||to_char((v_rev-v_committed)/100.0,'FM999999990.00'));

  v_payload := jsonb_build_object('verdict',v_verdict,'paying_members',v_members,
    'membership_revenue_cents',v_rev,'referral_paid_cents',v_credited,
    'referral_pending_cents',v_pending,'net_cents',v_rev-v_committed);

  -- In-app notification (idempotent per day).
  FOR a IN SELECT id FROM users WHERE role='admin' LOOP
    IF NOT EXISTS (SELECT 1 FROM notifications n WHERE n.user_id=a.id AND n.type='referral_guardian'
                   AND (n.created_at AT TIME ZONE 'America/Jamaica')::date = (now() AT TIME ZONE 'America/Jamaica')::date) THEN
      INSERT INTO notifications(user_id, title, body, type, data)
      VALUES (a.id, v_title, v_body, 'referral_guardian', v_payload);
    END IF;
  END LOOP;

  -- Email the verdict to admins (fire-and-forget; needs automation_service_key).
  SELECT value INTO v_key FROM app_config WHERE key='automation_service_key';
  IF v_key IS NOT NULL THEN
    BEGIN
      PERFORM extensions.http_post(
        url := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/referral-guardian-email',
        body := v_payload::text,
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key));
    EXCEPTION WHEN OTHERS THEN NULL;
    END;
  END IF;

  RETURN jsonb_build_object('verdict',v_verdict,'metrics',v_payload);
END;
$$;
REVOKE ALL ON FUNCTION public.referral_guardian_daily() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_guardian_daily() TO service_role;

-- Admin setter for the alert threshold (% of membership revenue).
CREATE OR REPLACE FUNCTION public.admin_set_referral_alert_pct(p_pct numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_admin uuid;
BEGIN
  v_admin := public.require_admin();
  IF p_pct IS NULL OR p_pct < 0 OR p_pct > 1000 THEN RAISE EXCEPTION 'pct out of range'; END IF;
  INSERT INTO app_config(key,value) VALUES ('referral_guardian_alert_pct', p_pct::text)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  RETURN jsonb_build_object('ok',true,'referral_guardian_alert_pct',p_pct);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_referral_alert_pct(numeric) TO authenticated;

NOTIFY pgrst, 'reload schema';
