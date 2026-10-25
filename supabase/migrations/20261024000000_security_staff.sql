-- ============================================================================
-- Cybersecurity AI Staff (3) + daily security assessment + admin alerting.
--
-- Three monitoring "staff" are added to the existing AI Staff platform:
--   * security_data_guardian  — RLS coverage, anon-executable SECURITY DEFINER
--                               functions (baseline + new/risky), grants.
--   * security_auth_sentinel  — admin accounts & MFA, failed-login / brute-force
--                               signals from the auth audit log, new privileged
--                               accounts.
--   * security_threat_monitor — money-movement and velocity anomalies
--                               (wallet, payments, orders, new accounts).
--
-- run_security_assessment() runs REAL, deterministic checks against the live
-- database every day, writes an ai_staff_report per role, logs every finding to
-- security_findings, and for HIGH/CRITICAL findings raises an ai_urgent_alert
-- and an in-app admin notification (balanced sensitivity). Advisory only — it
-- never changes data; it reports and alerts.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Findings history + the SECURITY DEFINER baseline.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.security_findings (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id      uuid,
  report_date date NOT NULL,
  staff_slug  text NOT NULL,
  domain      text NOT NULL,
  severity    text NOT NULL CHECK (severity IN ('critical','high','medium','low','info')),
  title       text NOT NULL,
  detail      jsonb NOT NULL DEFAULT '{}'::jsonb,
  status      text NOT NULL DEFAULT 'open' CHECK (status IN ('open','acknowledged','resolved')),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_security_findings_date ON public.security_findings(report_date DESC);
CREATE INDEX IF NOT EXISTS idx_security_findings_sev  ON public.security_findings(severity, status);
ALTER TABLE public.security_findings ENABLE ROW LEVEL SECURITY;

-- Baseline of anon-executable SECURITY DEFINER functions. Anything appearing
-- that is NOT in here is flagged as newly exposed, then recorded so it only
-- alerts once. Seeded with the current set so the first run is quiet.
CREATE TABLE IF NOT EXISTS public.security_secdef_baseline (
  signature  text PRIMARY KEY,
  first_seen timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.security_secdef_baseline ENABLE ROW LEVEL SECURITY;

-- Admins may read the findings (RLS). is_admin() already exists in this DB.
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='security_findings' AND policyname='security_findings_admin_read') THEN
    CREATE POLICY security_findings_admin_read ON public.security_findings
      FOR SELECT TO authenticated USING (public.is_admin());
  END IF;
END $$;

-- Seed the SECDEF baseline with today's anon-executable SECURITY DEFINER funcs.
INSERT INTO public.security_secdef_baseline(signature)
SELECT n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
ON CONFLICT (signature) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Register the 3 security staff (idempotent).
-- ---------------------------------------------------------------------------
INSERT INTO public.ai_staff_roles (slug, title, department, job_description, data_categories, daily_reporting_requirements, max_suggestions, model, status, sort_order)
VALUES
  ('security_data_guardian', 'Data Guardian', 'Security',
   'Protects all stored data. Audits row-level-security coverage, anon-executable SECURITY DEFINER functions, and privilege grants every day; flags any newly exposed function or table that could leak or alter data.',
   ARRAY['rls','functions','grants','schema'], 'Daily posture report: RLS coverage, new/changed anon-executable SECURITY DEFINER functions, grant changes. Alert on any RLS gap or newly exposed function.',
   3, 'gpt-4o-mini', 'active', 900),
  ('security_auth_sentinel', 'Access & Auth Sentinel', 'Security',
   'Watches authentication and privileged access. Monitors the auth audit log for failed-login and brute-force spikes, checks that admin accounts have MFA enrolled, and flags newly created privileged accounts.',
   ARRAY['auth','admin','mfa','sessions'], 'Daily report: failed-login volume, suspicious IPs, admin MFA coverage, new admin accounts. Alert on brute-force signals, admins without MFA, or new admins.',
   3, 'gpt-4o-mini', 'active', 901),
  ('security_threat_monitor', 'Threat Monitor', 'Security',
   'Detects abuse and fraud signals in live activity. Watches money movement (wallet, payments) and order/account velocity for anomalies that indicate account takeover, card testing, or scripted abuse.',
   ARRAY['wallet','payments','orders','accounts'], 'Daily report: money-movement anomalies, order and signup velocity, payment-failure spikes. Alert on abnormal money movement or velocity.',
   3, 'gpt-4o-mini', 'active', 902)
ON CONFLICT (slug) DO UPDATE
  SET title=EXCLUDED.title, department=EXCLUDED.department, job_description=EXCLUDED.job_description,
      data_categories=EXCLUDED.data_categories, daily_reporting_requirements=EXCLUDED.daily_reporting_requirements,
      status='active', updated_at=now();

-- ---------------------------------------------------------------------------
-- 3. The daily assessment engine.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_security_assessment(p_triggered_by text DEFAULT 'cron')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_date   date := (now() AT TIME ZONE 'America/Jamaica')::date;
  v_run    uuid;
  r_guard  uuid;
  r_auth   uuid;
  r_threat uuid;
  m jsonb;
  n_alerts int := 0;
  -- thresholds (balanced)
  c_failed_auth   int := 20;   -- failed auth events in 24h -> high
  c_ip_failed     int := 10;   -- failed auth from one IP in 24h -> high
  c_wallet_txns   int := 25;   -- wallet txns for one user in 24h -> high
  c_wallet_debit  numeric := 100000;  -- net debit for one user in 24h -> high
  c_order_vel     int := 15;   -- orders by one user in 24h -> medium
  c_new_accounts  int := 50;   -- new accounts in 24h -> medium
  c_failed_pay    int := 25;   -- failed payments in 24h -> high
BEGIN
  SELECT id INTO r_guard  FROM ai_staff_roles WHERE slug='security_data_guardian';
  SELECT id INTO r_auth   FROM ai_staff_roles WHERE slug='security_auth_sentinel';
  SELECT id INTO r_threat FROM ai_staff_roles WHERE slug='security_threat_monitor';

  INSERT INTO ai_report_runs(report_date, status, triggered_by, total_roles, completed_roles, failed_roles, started_at)
  VALUES (v_date, 'running', p_triggered_by, 3, 0, 0, now())
  RETURNING id INTO v_run;

  -- =========================================================================
  -- DATA GUARDIAN
  -- =========================================================================
  -- (a) RLS disabled on any public base table -> CRITICAL
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_data_guardian', 'rls', 'critical',
         'Table without row-level security: '||t.tablename,
         jsonb_build_object('table', t.tablename)
  FROM pg_tables t
  WHERE t.schemaname='public'
    AND NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace nn ON nn.oid=c.relnamespace
                    WHERE nn.nspname='public' AND c.relname=t.tablename AND c.relrowsecurity);

  -- (b) Newly exposed anon-executable SECURITY DEFINER functions -> HIGH
  CREATE TEMP TABLE _cur_secdef ON COMMIT DROP AS
  SELECT n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' AS sig
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef
    AND has_function_privilege('anon', p.oid, 'EXECUTE');

  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_data_guardian', 'functions', 'high',
         'New anon-executable SECURITY DEFINER function: '||c.sig,
         jsonb_build_object('signature', c.sig,
           'why','Runs with owner privileges and is callable by anonymous users. Review that it pins to auth.uid() and cannot be abused to read or change other users'' data.')
  FROM _cur_secdef c
  WHERE NOT EXISTS (SELECT 1 FROM security_secdef_baseline b WHERE b.signature=c.sig);

  -- record the new ones so they alert only once
  INSERT INTO security_secdef_baseline(signature)
  SELECT sig FROM _cur_secdef ON CONFLICT (signature) DO NOTHING;

  m := jsonb_build_object(
    'tables_total', (SELECT count(*) FROM pg_tables WHERE schemaname='public'),
    'rls_disabled', (SELECT count(*) FROM pg_tables t WHERE t.schemaname='public'
        AND NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace nn ON nn.oid=c.relnamespace
                        WHERE nn.nspname='public' AND c.relname=t.tablename AND c.relrowsecurity)),
    'anon_secdef_functions', (SELECT count(*) FROM _cur_secdef),
    'new_exposed_functions', (SELECT count(*) FROM security_findings WHERE run_id=v_run AND staff_slug='security_data_guardian' AND domain='functions')
  );
  INSERT INTO ai_staff_reports(run_id, role_id, report_date, status, summary, metrics, evidence, model)
  VALUES (v_run, r_guard, v_date, 'completed',
    'RLS coverage '||((m->>'tables_total')::int - (m->>'rls_disabled')::int)||'/'||(m->>'tables_total')||
    ' tables; '||(m->>'anon_secdef_functions')||' anon-executable SECURITY DEFINER functions, '||
    (m->>'new_exposed_functions')||' new since last run.',
    m,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('severity',severity,'title',title,'detail',detail))
              FROM security_findings WHERE run_id=v_run AND staff_slug='security_data_guardian'), '[]'::jsonb),
    'deterministic');

  -- =========================================================================
  -- ACCESS & AUTH SENTINEL
  -- =========================================================================
  -- (a) Admins without a verified MFA factor -> HIGH
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_auth_sentinel', 'mfa', 'high',
         'Admin without verified MFA: '||u.email,
         jsonb_build_object('user_id', u.id, 'email', u.email)
  FROM users u
  WHERE u.role='admin'
    AND NOT EXISTS (SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=u.id AND f.status='verified');

  -- (b) New admin accounts in the last 24h -> HIGH
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_auth_sentinel', 'admin', 'high',
         'New admin account created: '||u.email,
         jsonb_build_object('user_id', u.id, 'email', u.email, 'created_at', u.created_at)
  FROM users u
  WHERE u.role='admin' AND u.created_at > now() - interval '24 hours';

  -- (c) Failed-auth volume + brute-force by IP (from the auth audit log) -> HIGH
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_auth_sentinel', 'auth', 'high',
         'Elevated failed-login volume in the last 24h',
         jsonb_build_object('failed_events', cnt)
  FROM (SELECT count(*) cnt FROM auth.audit_log_entries
        WHERE created_at > now() - interval '24 hours'
          AND ((payload->>'action') ILIKE '%fail%' OR (payload::jsonb ? 'error'))) q
  WHERE q.cnt >= c_failed_auth;

  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_auth_sentinel', 'auth', 'high',
         'Possible brute force from IP '||ip_address,
         jsonb_build_object('ip', ip_address, 'failed_events', cnt)
  FROM (SELECT ip_address, count(*) cnt FROM auth.audit_log_entries
        WHERE created_at > now() - interval '24 hours'
          AND ((payload->>'action') ILIKE '%fail%' OR (payload::jsonb ? 'error'))
          AND ip_address IS NOT NULL
        GROUP BY ip_address) q
  WHERE q.cnt >= c_ip_failed;

  m := jsonb_build_object(
    'admins', (SELECT count(*) FROM users WHERE role='admin'),
    'admins_without_mfa', (SELECT count(*) FROM users u WHERE u.role='admin'
        AND NOT EXISTS (SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=u.id AND f.status='verified')),
    'auth_events_24h', (SELECT count(*) FROM auth.audit_log_entries WHERE created_at > now() - interval '24 hours'),
    'failed_auth_24h', (SELECT count(*) FROM auth.audit_log_entries WHERE created_at > now() - interval '24 hours'
        AND ((payload->>'action') ILIKE '%fail%' OR (payload::jsonb ? 'error')))
  );
  INSERT INTO ai_staff_reports(run_id, role_id, report_date, status, summary, metrics, evidence, model)
  VALUES (v_run, r_auth, v_date, 'completed',
    (m->>'admins')||' admin account(s), '||(m->>'admins_without_mfa')||' without MFA; '||
    (m->>'failed_auth_24h')||' failed auth events in 24h.',
    m,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('severity',severity,'title',title,'detail',detail))
              FROM security_findings WHERE run_id=v_run AND staff_slug='security_auth_sentinel'), '[]'::jsonb),
    'deterministic');

  -- =========================================================================
  -- THREAT MONITOR
  -- =========================================================================
  -- (a) Abnormal wallet activity for one user in 24h -> HIGH
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_threat_monitor', 'wallet', 'high',
         'Abnormal wallet activity for one account',
         jsonb_build_object('user_id', user_id, 'txns_24h', txns, 'net_amount_24h', net)
  FROM (SELECT user_id, count(*) txns, sum(amount) net
        FROM wallet_transactions WHERE created_at > now() - interval '24 hours'
        GROUP BY user_id) q
  WHERE q.txns >= c_wallet_txns OR q.net <= -c_wallet_debit;

  -- (b) Failed-payment spike in 24h -> HIGH (card testing signal)
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_threat_monitor', 'payments', 'high',
         'Elevated failed-payment volume in the last 24h',
         jsonb_build_object('failed_payments_24h', cnt)
  FROM (SELECT count(*) cnt FROM payments
        WHERE created_at > now() - interval '24 hours' AND status='failed') q
  WHERE q.cnt >= c_failed_pay;

  -- (c) Order velocity for one user in 24h -> MEDIUM (logged, not alerted)
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_threat_monitor', 'orders', 'medium',
         'High order velocity for one account',
         jsonb_build_object('user_id', user_id, 'orders_24h', cnt)
  FROM (SELECT user_id, count(*) cnt FROM orders
        WHERE created_at > now() - interval '24 hours' GROUP BY user_id) q
  WHERE q.cnt >= c_order_vel;

  -- (d) New-account velocity -> MEDIUM (logged, not alerted)
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_threat_monitor', 'accounts', 'medium',
         'Elevated new-account signups in the last 24h',
         jsonb_build_object('new_accounts_24h', cnt)
  FROM (SELECT count(*) cnt FROM users WHERE created_at > now() - interval '24 hours') q
  WHERE q.cnt >= c_new_accounts;

  m := jsonb_build_object(
    'wallet_txns_24h', (SELECT count(*) FROM wallet_transactions WHERE created_at > now() - interval '24 hours'),
    'failed_payments_24h', (SELECT count(*) FROM payments WHERE created_at > now() - interval '24 hours' AND status='failed'),
    'orders_24h', (SELECT count(*) FROM orders WHERE created_at > now() - interval '24 hours'),
    'new_accounts_24h', (SELECT count(*) FROM users WHERE created_at > now() - interval '24 hours')
  );
  INSERT INTO ai_staff_reports(run_id, role_id, report_date, status, summary, metrics, evidence, model)
  VALUES (v_run, r_threat, v_date, 'completed',
    (m->>'orders_24h')||' orders, '||(m->>'wallet_txns_24h')||' wallet txns, '||
    (m->>'failed_payments_24h')||' failed payments, '||(m->>'new_accounts_24h')||' new accounts in 24h.',
    m,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('severity',severity,'title',title,'detail',detail))
              FROM security_findings WHERE run_id=v_run AND staff_slug='security_threat_monitor'), '[]'::jsonb),
    'deterministic');

  -- =========================================================================
  -- ALERTS + ADMIN NOTIFICATIONS for HIGH/CRITICAL (balanced sensitivity)
  -- =========================================================================
  INSERT INTO ai_urgent_alerts(role_id, report_id, report_date, severity, title, message, evidence, status)
  SELECT
    (SELECT id FROM ai_staff_roles WHERE slug=f.staff_slug),
    (SELECT id FROM ai_staff_reports WHERE run_id=v_run AND role_id=(SELECT id FROM ai_staff_roles WHERE slug=f.staff_slug) LIMIT 1),
    v_date, f.severity, f.title,
    'Detected by the '||(SELECT title FROM ai_staff_roles WHERE slug=f.staff_slug)||' during the daily security assessment.',
    f.detail, 'open'
  FROM security_findings f
  WHERE f.run_id=v_run AND f.severity IN ('critical','high');
  GET DIAGNOSTICS n_alerts = ROW_COUNT;

  -- One in-app notification per admin, per high/critical finding.
  INSERT INTO notifications(user_id, type, title, body, data)
  SELECT u.id, 'security_alert', '🔐 '||f.severity||': '||f.title,
         'Security assessment flagged a '||f.severity||' issue. Open the Security dashboard to review.',
         jsonb_build_object('severity', f.severity, 'domain', f.domain, 'finding', f.detail, 'report_date', v_date)
  FROM security_findings f
  CROSS JOIN users u
  WHERE f.run_id=v_run AND f.severity IN ('critical','high') AND u.role='admin';

  UPDATE ai_report_runs
  SET status='completed', completed_roles=3, failed_roles=0, completed_at=now()
  WHERE id=v_run;

  RETURN jsonb_build_object(
    'run_id', v_run, 'date', v_date,
    'findings', (SELECT count(*) FROM security_findings WHERE run_id=v_run),
    'critical', (SELECT count(*) FROM security_findings WHERE run_id=v_run AND severity='critical'),
    'high',     (SELECT count(*) FROM security_findings WHERE run_id=v_run AND severity='high'),
    'alerts_raised', n_alerts
  );
END $function$;

-- Service role / direct SQL only. Never anon or ordinary users. Supabase
-- default-grants EXECUTE on new functions to anon/authenticated directly, so we
-- must revoke from them explicitly, not just from PUBLIC.
REVOKE ALL ON FUNCTION public.run_security_assessment(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_security_assessment(text) TO service_role;

-- ---------------------------------------------------------------------------
-- 4. Schedule it daily (06:00 UTC ≈ 01:00 Jamaica) via pg_cron.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM cron.unschedule('daily_security_assessment');
EXCEPTION WHEN OTHERS THEN NULL;
END $$;
SELECT cron.schedule('daily_security_assessment', '0 6 * * *',
  $$SELECT public.run_security_assessment('cron');$$);

NOTIFY pgrst, 'reload schema';
