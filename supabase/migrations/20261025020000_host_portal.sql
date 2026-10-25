-- ============================================================================
-- Host Rewards Phase 5: host portal. Hosts log in through the existing auth with
-- role='host' and see ONLY their own data (RLS-scoped). Admins link a host record
-- to a login. No second auth system.
-- ============================================================================

-- 1. Allow the 'host' role (widen the existing CHECK, keeping every current value).
DO $$
DECLARE c text;
BEGIN
  SELECT conname INTO c FROM pg_constraint
   WHERE conrelid='public.users'::regclass AND contype='c'
     AND pg_get_constraintdef(oid) ILIKE '%role = ANY%';
  IF c IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.users DROP CONSTRAINT %I', c);
  END IF;
  ALTER TABLE public.users ADD CONSTRAINT users_role_check CHECK (
    role = ANY (ARRAY['user','customer','driver','restaurant','admin',
                      'service_provider','laundry_provider','host'])
  );
END $$;

-- 2. Link a host record to a login account.
ALTER TABLE public.hosts ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES public.users(id);
CREATE INDEX IF NOT EXISTS idx_hosts_user ON public.hosts(user_id);

-- 3. Helper: the host id owned by the current auth user (NULL if none).
CREATE OR REPLACE FUNCTION public.host_my_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT id FROM hosts WHERE user_id = auth.uid() LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.host_my_id() TO authenticated;
REVOKE ALL ON FUNCTION public.host_my_id() FROM public, anon;

-- 4. Self-read RLS so a host sees only their own rows (admin policies remain).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='hosts' AND policyname='hosts_self_read') THEN
    CREATE POLICY hosts_self_read ON public.hosts
      FOR SELECT TO authenticated USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='host_properties' AND policyname='host_properties_self_read') THEN
    CREATE POLICY host_properties_self_read ON public.host_properties
      FOR SELECT TO authenticated
      USING (host_id IN (SELECT id FROM hosts WHERE user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='host_commissions' AND policyname='host_commissions_self_read') THEN
    CREATE POLICY host_commissions_self_read ON public.host_commissions
      FOR SELECT TO authenticated
      USING (host_id IN (SELECT id FROM hosts WHERE user_id = auth.uid()));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='host_payouts' AND policyname='host_payouts_self_read') THEN
    CREATE POLICY host_payouts_self_read ON public.host_payouts
      FOR SELECT TO authenticated
      USING (host_id IN (SELECT id FROM hosts WHERE user_id = auth.uid()));
  END IF;
END $$;

-- 5. Host-facing dashboard summary (own data only, pinned to auth.uid()).
CREATE OR REPLACE FUNCTION public.host_my_dashboard()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE h uuid; out jsonb;
BEGIN
  SELECT id INTO h FROM hosts WHERE user_id = auth.uid() LIMIT 1;
  IF h IS NULL THEN RETURN jsonb_build_object('is_host', false); END IF;
  SELECT jsonb_build_object(
    'is_host', true,
    'host_id', h,
    'properties', (SELECT count(*) FROM host_properties WHERE host_id=h),
    'referrals', (SELECT count(*) FROM host_referrals WHERE host_id=h AND status='active'),
    'pending_cents',  COALESCE((SELECT SUM(amount_cents) FROM host_commissions WHERE host_id=h AND status='pending'),0),
    'payable_cents',  COALESCE((SELECT SUM(amount_cents) FROM host_commissions WHERE host_id=h AND status='payable'),0),
    'paid_cents',     COALESCE((SELECT SUM(amount_cents) FROM host_commissions WHERE host_id=h AND status='paid'),0)
  ) INTO out;
  RETURN out;
END $$;
GRANT EXECUTE ON FUNCTION public.host_my_dashboard() TO authenticated;
REVOKE ALL ON FUNCTION public.host_my_dashboard() FROM public, anon;

-- 6. Admin: link a host to an existing login (by email) and grant the host role.
CREATE OR REPLACE FUNCTION public.host_admin_link_user(p_host_id uuid, p_email text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  SELECT id INTO v_uid FROM users WHERE lower(email) = lower(p_email) LIMIT 1;
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','no_user_with_email'); END IF;
  UPDATE hosts SET user_id = v_uid, updated_at=now() WHERE id = p_host_id;
  UPDATE users SET role='host' WHERE id = v_uid AND role NOT IN ('admin');
  PERFORM host_audit('host_login_linked','host',p_host_id, jsonb_build_object('user',v_uid,'email',p_email));
  RETURN jsonb_build_object('ok',true,'user_id',v_uid);
END $$;
REVOKE ALL ON FUNCTION public.host_admin_link_user(uuid, text) FROM public, anon;

NOTIFY pgrst, 'reload schema';
