-- ============================================================================
-- Linter cleanup (bounded, safe subset):
--  1. rls_policy_always_true (0024): tighten two INSERT policies that were
--     WITH CHECK (true).
--  2. public_bucket_allows_listing (0025): drop broad SELECT listing policies on
--     public buckets (public object URLs still work; only the list API is
--     removed). App does not .list() these buckets.
--  3. anon_security_definer_function_executable (0028): revoke anon EXECUTE on
--     admin_* SECURITY DEFINER functions (guests never call these; they're also
--     is_admin()-guarded internally). authenticated + service_role keep access.
--
-- NOT included here (need a careful, tested pass — would risk breaking guest
-- browsing / RLS evaluation / trigram+vector operators): the remaining
-- non-admin anon-executable functions and moving pg_trgm/vector/btree_gist out
-- of the public schema.
-- ============================================================================

-- 1) INSERT policies -----------------------------------------------------------
-- Notifications are created by triggers (SECURITY DEFINER) and the service role
-- (both bypass RLS); the app never client-inserts them. Restrict client INSERT
-- to admins instead of "anyone".
ALTER POLICY notifications_service_insert ON public.notifications
  WITH CHECK (public.is_admin());

-- A user may only file a deletion request for themselves.
ALTER POLICY deletion_requests_insert_public ON public.user_deletion_requests
  WITH CHECK (user_id = auth.uid());

-- 2) Public bucket listing -----------------------------------------------------
DROP POLICY IF EXISTS "Public read banner images"            ON storage.objects;
DROP POLICY IF EXISTS "car-service-images public read"       ON storage.objects;
DROP POLICY IF EXISTS "Public read category images"          ON storage.objects;
DROP POLICY IF EXISTS "Public logos"                         ON storage.objects;
DROP POLICY IF EXISTS "laundry logos public read"            ON storage.objects;
DROP POLICY IF EXISTS "marketing_content_bucket_public_read" ON storage.objects;
DROP POLICY IF EXISTS "vehicle_photos_public_read"           ON storage.objects;

-- 3) Revoke anon EXECUTE on admin_* SECURITY DEFINER functions -----------------
DO $do$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.prosecdef
      AND p.proname LIKE 'admin\_%'
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'admin_* funcs locked from anon: %', n;
END
$do$;

NOTIFY pgrst, 'reload schema';
