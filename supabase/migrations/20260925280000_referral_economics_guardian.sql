-- ============================================================================
-- AI Staff — Referral Economics Guardian. Watches the "Earn with HotBite"
-- referral programme so HotBite never gives back more than it earns: for every
-- order that pays referral rewards it compares the reward cost against the
-- platform revenue that order produced, flags net-negative activity and cap /
-- fraud anomalies, and posts a daily update (plus alerts) to admins.
-- ============================================================================

-- Config: alert when referral cost exceeds this % of the orders' platform revenue.
INSERT INTO app_config(key, value)
SELECT 'referral_guardian_alert_pct', '60'
WHERE NOT EXISTS (SELECT 1 FROM app_config WHERE key='referral_guardian_alert_pct');

-- 1. The AI staff role.
INSERT INTO ai_staff_roles (slug, title, department, job_description,
  data_categories, daily_reporting_requirements, max_suggestions, model, status, sort_order)
VALUES (
  'referral_economics_guardian', 'Referral Economics Guardian', 'Finance',
  'Protects HotBite from losing money on the Earn with HotBite referral programme. '
  || 'Each day compares referral rewards paid (Tier 1 $15 + Tiers 2-5 $2.50) against the '
  || 'platform revenue (commission, fee shares, HotBite member share) of the orders that '
  || 'triggered them, flags any order or day where reward cost exceeds revenue, watches for '
  || 'monthly-cap pressure and abnormal single-account earning (fraud), and updates admins.',
  ARRAY['referral_rewards','referral_cap_usage','orders','platform_revenue_ledger'],
  'Daily: reward orders, referral cost, order platform revenue, net contribution, '
  || 'net margin %, count of loss-making orders, top earners, cap usage, and a clear '
  || 'green/watch/alert verdict.',
  3, 'gpt-4o-mini', 'active', 60)
ON CONFLICT (slug) DO UPDATE SET
  title=EXCLUDED.title, department=EXCLUDED.department, job_description=EXCLUDED.job_description,
  data_categories=EXCLUDED.data_categories, daily_reporting_requirements=EXCLUDED.daily_reporting_requirements,
  status='active', updated_at=now();

-- 2. Economics over a window. Revenue is computed INLINE per order (commission +
--    platform delivery-fee share + service fee + HotBite member share) so it
--    works for every delivered order, not only those with a ledger row.
CREATE OR REPLACE FUNCTION public.admin_referral_economics(p_from timestamptz, p_to timestamptz)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v jsonb; v_driver numeric; v_alert_pct numeric;
BEGIN
  PERFORM public.require_admin();
  SELECT COALESCE(NULLIF(value,'')::numeric,0.80) INTO v_driver FROM app_config WHERE key='driver_pay_percent';
  v_driver := COALESCE(v_driver,0.80);
  SELECT COALESCE(NULLIF(value,'')::numeric,60) INTO v_alert_pct FROM app_config WHERE key='referral_guardian_alert_pct';

  WITH ro AS (
    SELECT o.id,
      round((COALESCE(o.commission_amount, COALESCE(o.subtotal,0)*COALESCE(o.commission_rate,0))
            + COALESCE(o.delivery_fee,0)*(1-v_driver)
            + COALESCE(o.platform_service_fee,0)
            + COALESCE(o.hotbite_savings_share,0)) * 100)::bigint AS rev_cents,
      (SELECT COALESCE(sum(rr.reward_cents),0) FROM referral_rewards rr
         WHERE rr.source_order_id=o.id AND rr.status<>'reversed')::bigint AS cost_cents
    FROM orders o
    WHERE o.status='delivered'
      AND COALESCE(o.delivered_at,o.created_at) >= p_from AND COALESCE(o.delivered_at,o.created_at) < p_to
      AND EXISTS (SELECT 1 FROM referral_rewards rr WHERE rr.source_order_id=o.id AND rr.status<>'reversed')
  )
  SELECT jsonb_build_object(
    'reward_orders', count(*),
    'referral_cost_cents', COALESCE(sum(cost_cents),0),
    'order_revenue_cents', COALESCE(sum(rev_cents),0),
    'net_contribution_cents', COALESCE(sum(rev_cents - cost_cents),0),
    'net_margin_pct', CASE WHEN COALESCE(sum(rev_cents),0)>0
        THEN round(100.0*sum(rev_cents-cost_cents)/sum(rev_cents),1) ELSE NULL END,
    'cost_to_revenue_pct', CASE WHEN COALESCE(sum(rev_cents),0)>0
        THEN round(100.0*sum(cost_cents)/sum(rev_cents),1) ELSE NULL END,
    'loss_making_orders', count(*) FILTER (WHERE cost_cents > rev_cents),
    'alert_threshold_pct', v_alert_pct,
    'verdict', CASE
        WHEN COALESCE(sum(rev_cents-cost_cents),0) < 0 THEN 'alert_losing'
        WHEN COALESCE(sum(rev_cents),0)>0 AND 100.0*sum(cost_cents)/sum(rev_cents) > v_alert_pct THEN 'watch'
        ELSE 'healthy' END
  ) INTO v FROM ro;

  -- Top earners this window (fraud watch).
  v := v || jsonb_build_object('top_earners', COALESCE((
    SELECT jsonb_agg(t) FROM (
      SELECT public.referral_mask_name(u.name) AS earner,
             sum(rr.reward_cents) AS cents,
             count(DISTINCT rr.source_order_id) AS orders
      FROM referral_rewards rr JOIN users u ON u.id=rr.earner_id
      WHERE rr.status IN ('pending','credited') AND rr.created_at>=p_from AND rr.created_at<p_to
      GROUP BY rr.earner_id, u.name ORDER BY sum(rr.reward_cents) DESC LIMIT 5
    ) t), '[]'::jsonb));

  RETURN v;
END;
$$;

-- 3. Daily guardian: compute yesterday+today window economics and post an admin
--    update (idempotent per Jamaica day). Alerts when losing / over threshold.
CREATE OR REPLACE FUNCTION public.referral_guardian_daily()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_day date := public.hotbite_month_key(now()); -- month bucket unused; day below
  v_from timestamptz; v_to timestamptz; e jsonb; v_verdict text;
  v_driver numeric; v_alert_pct numeric; a record; v_title text; v_body text;
BEGIN
  v_from := (date_trunc('day', now() AT TIME ZONE 'America/Jamaica')) AT TIME ZONE 'America/Jamaica';
  v_to   := v_from + interval '1 day';
  SELECT COALESCE(NULLIF(value,'')::numeric,0.80) INTO v_driver FROM app_config WHERE key='driver_pay_percent';
  v_driver := COALESCE(v_driver,0.80);
  SELECT COALESCE(NULLIF(value,'')::numeric,60) INTO v_alert_pct FROM app_config WHERE key='referral_guardian_alert_pct';

  WITH ro AS (
    SELECT o.id,
      round((COALESCE(o.commission_amount, COALESCE(o.subtotal,0)*COALESCE(o.commission_rate,0))
            + COALESCE(o.delivery_fee,0)*(1-v_driver) + COALESCE(o.platform_service_fee,0)
            + COALESCE(o.hotbite_savings_share,0)) * 100)::bigint AS rev_cents,
      (SELECT COALESCE(sum(rr.reward_cents),0) FROM referral_rewards rr
         WHERE rr.source_order_id=o.id AND rr.status<>'reversed')::bigint AS cost_cents
    FROM orders o
    WHERE o.status='delivered' AND COALESCE(o.delivered_at,o.created_at)>=v_from
      AND COALESCE(o.delivered_at,o.created_at)<v_to
      AND EXISTS (SELECT 1 FROM referral_rewards rr WHERE rr.source_order_id=o.id AND rr.status<>'reversed')
  )
  SELECT jsonb_build_object(
    'reward_orders', count(*), 'cost', COALESCE(sum(cost_cents),0),
    'revenue', COALESCE(sum(rev_cents),0), 'net', COALESCE(sum(rev_cents-cost_cents),0),
    'loss_orders', count(*) FILTER (WHERE cost_cents>rev_cents)) INTO e FROM ro;

  v_verdict := CASE
    WHEN (e->>'net')::bigint < 0 THEN 'ALERT'
    WHEN (e->>'revenue')::bigint>0 AND 100.0*(e->>'cost')::bigint/(e->>'revenue')::bigint > v_alert_pct THEN 'WATCH'
    ELSE 'OK' END;

  v_title := 'Referral programme — '||v_verdict;
  v_body := format('Today: %s reward orders · cost %s · order revenue %s · net %s%s',
    (e->>'reward_orders'),
    '$'||to_char(((e->>'cost')::numeric/100),'FM999999990.00'),
    '$'||to_char(((e->>'revenue')::numeric/100),'FM999999990.00'),
    '$'||to_char(((e->>'net')::numeric/100),'FM999999990.00'),
    CASE WHEN (e->>'loss_orders')::int>0 THEN ' · '||(e->>'loss_orders')||' loss-making' ELSE '' END);

  -- One update per admin per day (idempotent).
  FOR a IN SELECT id FROM users WHERE role='admin' LOOP
    IF NOT EXISTS (SELECT 1 FROM notifications n WHERE n.user_id=a.id AND n.type='referral_guardian'
                   AND (n.created_at AT TIME ZONE 'America/Jamaica')::date = (now() AT TIME ZONE 'America/Jamaica')::date) THEN
      INSERT INTO notifications(user_id, title, body, type, data)
      VALUES (a.id, v_title, v_body, 'referral_guardian',
              e || jsonb_build_object('verdict', v_verdict));
    END IF;
  END LOOP;

  RETURN jsonb_build_object('verdict', v_verdict, 'metrics', e);
END;
$$;

REVOKE ALL ON FUNCTION public.referral_guardian_daily() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_guardian_daily() TO service_role;
GRANT EXECUTE ON FUNCTION public.admin_referral_economics(timestamptz,timestamptz) TO authenticated;

-- Daily at 07:00 UTC (~02:00 Jamaica).
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
    PERFORM cron.unschedule('referral-guardian-daily') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname='referral-guardian-daily');
    PERFORM cron.schedule('referral-guardian-daily','0 7 * * *', $c$ SELECT public.referral_guardian_daily(); $c$);
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
