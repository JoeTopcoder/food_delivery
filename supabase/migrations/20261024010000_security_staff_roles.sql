-- ============================================================================
-- Realign the 3 cybersecurity staff to the formal role structure (NIST CSF /
-- OWASP aligned) and extend the daily assessment with the checks each role owns.
--
--   security_lead_ir      — Cybersecurity Lead & Incident Response Officer
--   security_appsec       — Application & API Security Engineer
--   security_infra_access — Cloud, Infrastructure & Access Security Engineer
--
-- Builds on 20261024000000_security_staff.sql (keeps the same role rows/ids,
-- findings table, SECDEF baseline, cron job, and admin-alert plumbing).
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Generic baseline (public buckets, permissive RLS policies). Like the SECDEF
-- baseline: seed the current set so only NEW exposures alert later.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.security_baseline (
  kind       text NOT NULL,
  signature  text NOT NULL,
  first_seen timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (kind, signature)
);
ALTER TABLE public.security_baseline ENABLE ROW LEVEL SECURITY;

-- Seed: public storage buckets
INSERT INTO public.security_baseline(kind, signature)
SELECT 'bucket', name FROM storage.buckets WHERE public = true
ON CONFLICT DO NOTHING;

-- Seed: permissive (USING true) RLS policies
INSERT INTO public.security_baseline(kind, signature)
SELECT 'policy', schemaname||'.'||tablename||'.'||policyname
FROM pg_policies WHERE schemaname='public' AND qual='true'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- Re-title / re-scope the 3 staff (slugs change; row ids stay the same).
-- ---------------------------------------------------------------------------
UPDATE public.ai_staff_roles SET
  slug='security_appsec',
  title='Application & API Security Engineer',
  job_description='Finds and helps fix weaknesses in HotBite''s software before attackers do. Verifies role-based access (customers cannot see other customers'' orders/addresses, drivers scoped to their deliveries, restaurants isolated, staff cannot do admin actions), that prices/discounts/refunds/order-status/payment are enforced by the backend not the client, payment-notification authenticity, and that no new function or policy is over-exposed.',
  daily_reporting_requirements='Daily: RLS coverage, new anon-executable SECURITY DEFINER functions, new permissive RLS policies, backend price-guard integrity. Alert on any RLS gap, newly exposed function/policy, or missing price guard.',
  sort_order=901, status='active', updated_at=now()
WHERE slug='security_data_guardian';

UPDATE public.ai_staff_roles SET
  slug='security_infra_access',
  title='Cloud, Infrastructure & Access Security Engineer',
  job_description='Protects the systems and accounts that keep HotBite running: cloud/storage settings, databases, privileged accounts, secrets and backups. Ensures databases/backups/private files are not public, MFA on privileged accounts, least-privilege access, and prompt removal of access when staff change roles.',
  daily_reporting_requirements='Daily: admin/privileged account inventory & MFA coverage, newly public storage buckets, new privileged accounts. Alert on admins without MFA, new admins, or newly public buckets.',
  sort_order=902, status='active', updated_at=now()
WHERE slug='security_auth_sentinel';

UPDATE public.ai_staff_roles SET
  slug='security_lead_ir',
  title='Cybersecurity Lead & Incident Response Officer',
  job_description='Keeps an overall view of HotBite''s security and makes sure risks are addressed. Reviews alerts for suspicious logins, unusual activity, unauthorized admin actions and account takeovers; coordinates incident response; tracks open incidents to closure; and reports posture to management.',
  daily_reporting_requirements='Daily: failed-login/brute-force signals, money-movement & velocity anomalies, open incident aging, overall posture. Alert on attack signals and abnormal money movement; escalate unresolved critical/high incidents.',
  sort_order=900, status='active', updated_at=now()
WHERE slug='security_threat_monitor';

-- ---------------------------------------------------------------------------
-- Rebuild the assessment engine around the three owners + new checks.
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
  r_lead   uuid;
  r_app    uuid;
  r_infra  uuid;
  sec_roles uuid[];
  v_created boolean := false;
  m jsonb;
  n_alerts int := 0;
  expected_guards text[] := ARRAY['trg_ai_guard_menus','trg_ai_guard_restaurants','trg_ai_guard_app_config'];
  -- thresholds (balanced)
  c_failed_auth  int := 20;
  c_ip_failed    int := 10;
  c_wallet_txns  int := 25;
  c_wallet_debit numeric := 100000;
  c_order_vel    int := 15;
  c_new_accounts int := 50;
  c_failed_pay   int := 25;
  c_incident_age int := 7;   -- days an open high/critical incident may age
BEGIN
  SELECT id INTO r_lead  FROM ai_staff_roles WHERE slug='security_lead_ir';
  SELECT id INTO r_app   FROM ai_staff_roles WHERE slug='security_appsec';
  SELECT id INTO r_infra FROM ai_staff_roles WHERE slug='security_infra_access';
  sec_roles := ARRAY[r_lead, r_app, r_infra];

  -- One run row per day is shared across the whole AI staff platform (unique on
  -- report_date). Reuse today's if it exists, else create it. Then make this
  -- assessment idempotent: clear only THIS run's security-authored artifacts so
  -- an on-demand re-run replaces today's security results cleanly.
  SELECT id INTO v_run FROM ai_report_runs WHERE report_date = v_date;
  IF v_run IS NULL THEN
    INSERT INTO ai_report_runs(report_date, status, triggered_by, total_roles, completed_roles, failed_roles, started_at)
    VALUES (v_date, 'running', p_triggered_by, 3, 0, 0, now()) RETURNING id INTO v_run;
    v_created := true;
  END IF;

  DELETE FROM ai_urgent_alerts
  WHERE report_id IN (SELECT id FROM ai_staff_reports WHERE run_id=v_run AND role_id = ANY(sec_roles));
  DELETE FROM ai_staff_reports WHERE run_id=v_run AND role_id = ANY(sec_roles);
  DELETE FROM security_findings WHERE run_id=v_run;
  DELETE FROM notifications WHERE type='security_alert' AND (data->>'report_date') = v_date::text;

  -- =========================================================================
  -- APPLICATION & API SECURITY  (security_appsec)
  -- =========================================================================
  -- (a) RLS disabled on any public base table -> CRITICAL
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_appsec', 'rls', 'critical',
         'Table without row-level security: '||t.tablename, jsonb_build_object('table', t.tablename)
  FROM pg_tables t
  WHERE t.schemaname='public'
    AND NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace nn ON nn.oid=c.relnamespace
                    WHERE nn.nspname='public' AND c.relname=t.tablename AND c.relrowsecurity);

  -- (b) New anon-executable SECURITY DEFINER functions -> HIGH
  DROP TABLE IF EXISTS _cur_secdef;
  CREATE TEMP TABLE _cur_secdef ON COMMIT DROP AS
  SELECT n.nspname||'.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' AS sig
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('anon', p.oid, 'EXECUTE');

  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_appsec', 'functions', 'high',
         'New anon-executable SECURITY DEFINER function: '||c.sig,
         jsonb_build_object('signature', c.sig, 'why','Runs with owner privileges and is callable anonymously. Verify it pins to auth.uid() and cannot read/alter other users'' data.')
  FROM _cur_secdef c
  WHERE NOT EXISTS (SELECT 1 FROM security_secdef_baseline b WHERE b.signature=c.sig);
  INSERT INTO security_secdef_baseline(signature) SELECT sig FROM _cur_secdef ON CONFLICT (signature) DO NOTHING;

  -- (c) New permissive (USING true) RLS policy -> HIGH
  DROP TABLE IF EXISTS _cur_pol;
  CREATE TEMP TABLE _cur_pol ON COMMIT DROP AS
  SELECT schemaname||'.'||tablename||'.'||policyname AS sig
  FROM pg_policies WHERE schemaname='public' AND qual='true';

  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_appsec', 'policy', 'high',
         'New permissive (USING true) RLS policy: '||c.sig,
         jsonb_build_object('policy', c.sig, 'why','A USING(true) policy lets every row be read/written. Confirm it is intended public data, not a cross-tenant leak.')
  FROM _cur_pol c
  WHERE NOT EXISTS (SELECT 1 FROM security_baseline b WHERE b.kind='policy' AND b.signature=c.sig);
  INSERT INTO security_baseline(kind, signature) SELECT 'policy', sig FROM _cur_pol ON CONFLICT DO NOTHING;

  -- (d) Backend price-guard integrity: each expected ai_guard trigger present -> HIGH if missing
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_appsec', 'integrity', 'high',
         'Backend price-guard trigger missing: '||g,
         jsonb_build_object('trigger', g, 'why','The ai_guard price-write protection is not attached; backend price authority is weakened.')
  FROM unnest(expected_guards) g
  WHERE NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname=g AND NOT tgisinternal);

  m := jsonb_build_object(
    'tables_total', (SELECT count(*) FROM pg_tables WHERE schemaname='public'),
    'rls_disabled', (SELECT count(*) FROM pg_tables t WHERE t.schemaname='public'
        AND NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace nn ON nn.oid=c.relnamespace
                        WHERE nn.nspname='public' AND c.relname=t.tablename AND c.relrowsecurity)),
    'anon_secdef_functions', (SELECT count(*) FROM _cur_secdef),
    'permissive_policies', (SELECT count(*) FROM _cur_pol),
    'caller_id_secdef', (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
        WHERE n.nspname='public' AND p.prosecdef AND has_function_privilege('authenticated', p.oid, 'EXECUTE')
          AND pg_get_function_identity_arguments(p.oid) ~* '(user_id|sender_id)'),
    'price_guards_present', (SELECT count(*) FROM unnest(expected_guards) g WHERE EXISTS (SELECT 1 FROM pg_trigger WHERE tgname=g AND NOT tgisinternal))
  );
  INSERT INTO ai_staff_reports(run_id, role_id, report_date, status, summary, metrics, evidence, model)
  VALUES (v_run, r_app, v_date, 'completed',
    'RLS '||((m->>'tables_total')::int-(m->>'rls_disabled')::int)||'/'||(m->>'tables_total')||' tables; '||
    (m->>'anon_secdef_functions')||' anon SECDEF fns; '||(m->>'permissive_policies')||' permissive policies; price-guards '||
    (m->>'price_guards_present')||'/3.',
    m,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('severity',severity,'title',title,'detail',detail))
              FROM security_findings WHERE run_id=v_run AND staff_slug='security_appsec'), '[]'::jsonb),
    'deterministic');

  -- =========================================================================
  -- CLOUD, INFRASTRUCTURE & ACCESS  (security_infra_access)
  -- =========================================================================
  -- (a) Admins without verified MFA -> HIGH
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_infra_access', 'mfa', 'high',
         'Admin without verified MFA: '||u.email, jsonb_build_object('user_id', u.id, 'email', u.email)
  FROM users u WHERE u.role='admin'
    AND NOT EXISTS (SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=u.id AND f.status='verified');

  -- (b) New admin account in last 24h -> HIGH
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_infra_access', 'admin', 'high',
         'New admin account created: '||u.email, jsonb_build_object('user_id', u.id, 'email', u.email, 'created_at', u.created_at)
  FROM users u WHERE u.role='admin' AND u.created_at > now() - interval '24 hours';

  -- (c) Newly public storage bucket -> HIGH
  DROP TABLE IF EXISTS _cur_bucket;
  CREATE TEMP TABLE _cur_bucket ON COMMIT DROP AS
  SELECT name AS sig FROM storage.buckets WHERE public = true;

  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_infra_access', 'storage', 'high',
         'Newly public storage bucket: '||c.sig,
         jsonb_build_object('bucket', c.sig, 'why','A public bucket is readable by anyone with the URL. Confirm it holds only non-sensitive assets.')
  FROM _cur_bucket c
  WHERE NOT EXISTS (SELECT 1 FROM security_baseline b WHERE b.kind='bucket' AND b.signature=c.sig);
  INSERT INTO security_baseline(kind, signature) SELECT 'bucket', sig FROM _cur_bucket ON CONFLICT DO NOTHING;

  m := jsonb_build_object(
    'admins', (SELECT count(*) FROM users WHERE role='admin'),
    'admins_without_mfa', (SELECT count(*) FROM users u WHERE u.role='admin'
        AND NOT EXISTS (SELECT 1 FROM auth.mfa_factors f WHERE f.user_id=u.id AND f.status='verified')),
    'total_buckets', (SELECT count(*) FROM storage.buckets),
    'public_buckets', (SELECT count(*) FROM _cur_bucket)
  );
  INSERT INTO ai_staff_reports(run_id, role_id, report_date, status, summary, metrics, evidence, model)
  VALUES (v_run, r_infra, v_date, 'completed',
    (m->>'admins')||' admin(s), '||(m->>'admins_without_mfa')||' without MFA; '||
    (m->>'public_buckets')||'/'||(m->>'total_buckets')||' storage buckets public.',
    m,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('severity',severity,'title',title,'detail',detail))
              FROM security_findings WHERE run_id=v_run AND staff_slug='security_infra_access'), '[]'::jsonb),
    'deterministic');

  -- =========================================================================
  -- CYBERSECURITY LEAD & INCIDENT RESPONSE  (security_lead_ir)
  -- =========================================================================
  -- (a) Failed-auth volume -> HIGH
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_lead_ir', 'auth', 'high',
         'Elevated failed-login volume in the last 24h', jsonb_build_object('failed_events', cnt)
  FROM (SELECT count(*) cnt FROM auth.audit_log_entries
        WHERE created_at > now() - interval '24 hours'
          AND ((payload->>'action') ILIKE '%fail%' OR (payload::jsonb ? 'error'))) q
  WHERE q.cnt >= c_failed_auth;

  -- (b) Brute force by IP -> HIGH
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_lead_ir', 'auth', 'high',
         'Possible brute force from IP '||ip_address, jsonb_build_object('ip', ip_address, 'failed_events', cnt)
  FROM (SELECT ip_address, count(*) cnt FROM auth.audit_log_entries
        WHERE created_at > now() - interval '24 hours'
          AND ((payload->>'action') ILIKE '%fail%' OR (payload::jsonb ? 'error')) AND ip_address IS NOT NULL
        GROUP BY ip_address) q
  WHERE q.cnt >= c_ip_failed;

  -- (c) Abnormal wallet activity for one user -> HIGH
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_lead_ir', 'wallet', 'high',
         'Abnormal wallet activity for one account',
         jsonb_build_object('user_id', user_id, 'txns_24h', txns, 'net_amount_24h', net)
  FROM (SELECT user_id, count(*) txns, sum(amount) net FROM wallet_transactions
        WHERE created_at > now() - interval '24 hours' GROUP BY user_id) q
  WHERE q.txns >= c_wallet_txns OR q.net <= -c_wallet_debit;

  -- (d) Failed-payment spike -> HIGH
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_lead_ir', 'payments', 'high',
         'Elevated failed-payment volume in the last 24h', jsonb_build_object('failed_payments_24h', cnt)
  FROM (SELECT count(*) cnt FROM payments WHERE created_at > now() - interval '24 hours' AND status='failed') q
  WHERE q.cnt >= c_failed_pay;

  -- (e) Order velocity -> MEDIUM
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_lead_ir', 'orders', 'medium',
         'High order velocity for one account', jsonb_build_object('user_id', user_id, 'orders_24h', cnt)
  FROM (SELECT user_id, count(*) cnt FROM orders WHERE created_at > now() - interval '24 hours' GROUP BY user_id) q
  WHERE q.cnt >= c_order_vel;

  -- (f) New-account velocity -> MEDIUM
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_lead_ir', 'accounts', 'medium',
         'Elevated new-account signups in the last 24h', jsonb_build_object('new_accounts_24h', cnt)
  FROM (SELECT count(*) cnt FROM users WHERE created_at > now() - interval '24 hours') q
  WHERE q.cnt >= c_new_accounts;

  -- (g) Open security incidents aging past SLA -> MEDIUM (escalation)
  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_lead_ir', 'incident', 'medium',
         cnt||' security alert(s) open longer than '||c_incident_age||' days',
         jsonb_build_object('aged_open_alerts', cnt)
  FROM (SELECT count(*) cnt FROM ai_urgent_alerts
        WHERE role_id = ANY(sec_roles) AND status='open'
          AND created_at < now() - make_interval(days => c_incident_age)) q
  WHERE q.cnt > 0;

  m := jsonb_build_object(
    'open_security_alerts', (SELECT count(*) FROM ai_urgent_alerts WHERE role_id = ANY(sec_roles) AND status='open'),
    'auth_events_24h', (SELECT count(*) FROM auth.audit_log_entries WHERE created_at > now() - interval '24 hours'),
    'failed_auth_24h', (SELECT count(*) FROM auth.audit_log_entries WHERE created_at > now() - interval '24 hours'
        AND ((payload->>'action') ILIKE '%fail%' OR (payload::jsonb ? 'error'))),
    'orders_24h', (SELECT count(*) FROM orders WHERE created_at > now() - interval '24 hours'),
    'wallet_txns_24h', (SELECT count(*) FROM wallet_transactions WHERE created_at > now() - interval '24 hours'),
    'failed_payments_24h', (SELECT count(*) FROM payments WHERE created_at > now() - interval '24 hours' AND status='failed'),
    'new_accounts_24h', (SELECT count(*) FROM users WHERE created_at > now() - interval '24 hours')
  );
  INSERT INTO ai_staff_reports(run_id, role_id, report_date, status, summary, metrics, evidence, model)
  VALUES (v_run, r_lead, v_date, 'completed',
    'Posture: '||(SELECT count(*) FROM security_findings WHERE run_id=v_run AND severity IN ('critical','high'))||
    ' high/critical finding(s) today; '||(m->>'open_security_alerts')||' open security alert(s); '||
    (m->>'failed_auth_24h')||' failed logins, '||(m->>'orders_24h')||' orders in 24h.',
    m,
    COALESCE((SELECT jsonb_agg(jsonb_build_object('severity',severity,'title',title,'detail',detail))
              FROM security_findings WHERE run_id=v_run AND staff_slug='security_lead_ir'), '[]'::jsonb),
    'deterministic');

  -- =========================================================================
  -- ALERTS + ADMIN NOTIFICATIONS for HIGH/CRITICAL
  -- =========================================================================
  INSERT INTO ai_urgent_alerts(role_id, report_id, report_date, severity, title, message, evidence, status)
  SELECT (SELECT id FROM ai_staff_roles WHERE slug=f.staff_slug),
         (SELECT id FROM ai_staff_reports WHERE run_id=v_run AND role_id=(SELECT id FROM ai_staff_roles WHERE slug=f.staff_slug) LIMIT 1),
         v_date, f.severity, f.title,
         'Detected by the '||(SELECT title FROM ai_staff_roles WHERE slug=f.staff_slug)||' during the daily security assessment.',
         f.detail, 'open'
  FROM security_findings f
  WHERE f.run_id=v_run AND f.severity IN ('critical','high');
  GET DIAGNOSTICS n_alerts = ROW_COUNT;

  INSERT INTO notifications(user_id, type, title, body, data)
  SELECT u.id, 'security_alert', '🔐 '||f.severity||': '||f.title,
         'Security assessment flagged a '||f.severity||' issue. Open the Security dashboard to review.',
         jsonb_build_object('severity', f.severity, 'domain', f.domain, 'finding', f.detail, 'report_date', v_date)
  FROM security_findings f CROSS JOIN users u
  WHERE f.run_id=v_run AND f.severity IN ('critical','high') AND u.role='admin';

  -- Only finalize the run row if WE created it (don't clobber a shared run the
  -- main AI staff platform owns).
  IF v_created THEN
    UPDATE ai_report_runs SET status='completed', completed_roles=3, failed_roles=0, completed_at=now() WHERE id=v_run;
  END IF;

  RETURN jsonb_build_object('run_id', v_run, 'date', v_date,
    'findings', (SELECT count(*) FROM security_findings WHERE run_id=v_run),
    'critical', (SELECT count(*) FROM security_findings WHERE run_id=v_run AND severity='critical'),
    'high',     (SELECT count(*) FROM security_findings WHERE run_id=v_run AND severity='high'),
    'alerts_raised', n_alerts);
END $function$;

REVOKE ALL ON FUNCTION public.run_security_assessment(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_security_assessment(text) TO service_role;

NOTIFY pgrst, 'reload schema';
