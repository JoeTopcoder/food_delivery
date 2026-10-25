-- ============================================================================
-- #2 Phased anon-revoke on guarded SECDEF RPCs + #1 unguarded-privileged detector.
--
-- #2: Revoke EXECUTE from PUBLIC/anon on the 23 non-trigger SECURITY DEFINER
--     functions that are gated by is_admin()/can_manage()/aal2 and are NOT used
--     in RLS policies. anon can never satisfy those guards, so removing anon is
--     lossless; authenticated keeps its direct grant and app flows are untouched.
--
-- #1: Add an AppSec check that flags anon-exec SECDEF functions taking a caller-
--     supplied user/driver/owner id with NO auth guard (the IDOR pattern that
--     caught _peak_set). Current offenders are baselined so the daily run reports
--     the standing count and alerts only on NEW ones.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- #2: Lossless anon revoke on admin/manager-gated, non-policy functions.
-- ---------------------------------------------------------------------------
DO $REVOKE$
DECLARE r record;
BEGIN
  FOR r IN
    WITH anon_secdef AS (
      SELECT p.oid, p.proname, 'public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' AS sig,
             pg_get_functiondef(p.oid) AS def
      FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.prosecdef AND p.prorettype<>'trigger'::regtype
        AND has_function_privilege('anon',p.oid,'EXECUTE')
    ),
    policy_fns AS (
      SELECT DISTINCT a.proname FROM anon_secdef a
      WHERE EXISTS (SELECT 1 FROM pg_policies pol WHERE pol.schemaname='public'
                    AND (coalesce(pol.qual,'')||' '||coalesce(pol.with_check,'')) ILIKE '%'||a.proname||'%')
    )
    SELECT sig FROM anon_secdef a
    WHERE (a.def ILIKE '%is_admin%' OR a.def ILIKE '%is_super_admin%' OR a.def ILIKE '%can_manage%' OR a.def ILIKE '%aal2%')
      AND a.proname NOT IN (SELECT proname FROM policy_fns)
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon', r.sig);
  END LOOP;
END $REVOKE$;

-- ---------------------------------------------------------------------------
-- #1: Seed the baseline of currently-unguarded privileged functions so the new
--     detector reports them as a standing count rather than alerting all at once.
-- ---------------------------------------------------------------------------
INSERT INTO public.security_baseline(kind, signature)
SELECT 'unguarded_fn', 'public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')'
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
WHERE n.nspname='public' AND p.prosecdef AND p.prorettype<>'trigger'::regtype
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
  AND pg_get_function_identity_arguments(p.oid) ~* '(user_id|sender_id|owner_id|driver_id|admin)'
  AND pg_get_functiondef(p.oid) NOT ILIKE '%auth.uid()%'
  AND pg_get_functiondef(p.oid) NOT ILIKE '%is_admin%'
  AND pg_get_functiondef(p.oid) NOT ILIKE '%is_super_admin%'
  AND pg_get_functiondef(p.oid) NOT ILIKE '%can_manage%'
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- #1: Extend the assessment with the unguarded-privileged detector.
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

  -- (e) Unguarded privileged function: anon-exec SECDEF taking a caller-supplied
  --     user/driver/owner id with NO auth check (IDOR / privilege-escalation
  --     pattern, e.g. get_recommendations(p_user_id) or a reward minter) -> HIGH
  DROP TABLE IF EXISTS _cur_unguarded;
  CREATE TEMP TABLE _cur_unguarded ON COMMIT DROP AS
  SELECT 'public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' AS sig
  FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
  WHERE n.nspname='public' AND p.prosecdef AND p.prorettype<>'trigger'::regtype
    AND has_function_privilege('anon', p.oid, 'EXECUTE')
    AND pg_get_function_identity_arguments(p.oid) ~* '(user_id|sender_id|owner_id|driver_id|admin)'
    AND pg_get_functiondef(p.oid) NOT ILIKE '%auth.uid()%'
    AND pg_get_functiondef(p.oid) NOT ILIKE '%is_admin%'
    AND pg_get_functiondef(p.oid) NOT ILIKE '%is_super_admin%'
    AND pg_get_functiondef(p.oid) NOT ILIKE '%can_manage%';

  INSERT INTO security_findings(run_id, report_date, staff_slug, domain, severity, title, detail)
  SELECT v_run, v_date, 'security_appsec', 'authz', 'high',
         'Unguarded privileged function (caller-supplied id, no auth check): '||c.sig,
         jsonb_build_object('signature', c.sig, 'why','Takes a user/driver/owner id but never checks auth.uid()/is_admin/can_manage, so any caller can act on another subject (IDOR). Pin the id to auth.uid() or restrict the function to service_role.')
  FROM _cur_unguarded c
  WHERE NOT EXISTS (SELECT 1 FROM security_baseline b WHERE b.kind='unguarded_fn' AND b.signature=c.sig);
  INSERT INTO security_baseline(kind, signature) SELECT 'unguarded_fn', sig FROM _cur_unguarded ON CONFLICT DO NOTHING;

  m := jsonb_build_object(
    'tables_total', (SELECT count(*) FROM pg_tables WHERE schemaname='public'),
    'rls_disabled', (SELECT count(*) FROM pg_tables t WHERE t.schemaname='public'
        AND NOT EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace nn ON nn.oid=c.relnamespace
                        WHERE nn.nspname='public' AND c.relname=t.tablename AND c.relrowsecurity)),
    'anon_secdef_functions', (SELECT count(*) FROM _cur_secdef),
    'permissive_policies', (SELECT count(*) FROM _cur_pol),
    'unguarded_privileged', (SELECT count(*) FROM _cur_unguarded),
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
END $function$;;


REVOKE ALL ON FUNCTION public.run_security_assessment(text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.run_security_assessment(text) TO service_role;

NOTIFY pgrst, 'reload schema';
