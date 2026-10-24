-- ============================================================================
-- Security hardening from the Supabase database-linter advisories (2026-10-24).
--
-- Scope = the SAFE, verified fixes only:
--   1. Lock down all SECURITY DEFINER *trigger* functions so they cannot be
--      called via /rest/v1/rpc. Triggers still fire (execution uses the table
--      owner's rights, not an EXECUTE grant), so this is zero-risk and removes
--      the whole class of "trigger function callable by anon" warnings.
--   2. Lock down two unguarded internal helpers that take a caller-supplied
--      privileged id with NO auth check (_peak_set, _ad_audit). Both are called
--      only by SECURITY DEFINER wrappers (admin_set_peak_time_config / the ad_*
--      functions), which keep working because they run with owner privileges.
--   3. Stop the public `ad-assets` bucket from allowing anyone to LIST every
--      file; object URLs still serve (public bucket). Listing is restricted to
--      admins, who are the only ones who browse it.
--
-- NOT touched here (documented, deliberately deferred):
--   * extension_in_public (vector, pg_trgm, btree_gist): moving these risks
--     breaking the search / exclusion-constraint indexes that depend on them;
--     low severity, handle separately with index rebuilds.
--   * The ~130 other anon-executable SECURITY DEFINER RPCs: verified they are
--     guarded internally (is_admin()/auth.uid()/can_manage_*) so anon calls fail
--     safe, OR are intentionally guest-facing (e.g. app_closure_status). A
--     blanket anon revoke would break guest flows and RLS helper usage, so those
--     are left for a per-function pass.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. Revoke EXECUTE on every SECURITY DEFINER trigger function in public.
-- ---------------------------------------------------------------------------
DO $$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT 'public.'||p.proname||'('||pg_get_function_identity_arguments(p.oid)||')' AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prosecdef AND p.prorettype = 'trigger'::regtype
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 2. Lock down the two unguarded internal helpers.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public._peak_set(p_admin uuid, p_key text, p_new text)
  FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._ad_audit(p_type text, p_id uuid, p_action text, p_reason text, p_meta jsonb)
  FROM PUBLIC, anon, authenticated;

-- ---------------------------------------------------------------------------
-- 3. ad-assets bucket: replace the broad public listing policy with an
--    admin-only one. Public object URLs are unaffected (bucket stays public).
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS ad_pub_read ON storage.objects;
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='storage' AND tablename='objects' AND policyname='ad_assets_admin_list') THEN
    CREATE POLICY ad_assets_admin_list ON storage.objects
      FOR SELECT TO authenticated
      USING (bucket_id = 'ad-assets' AND public.is_admin());
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
