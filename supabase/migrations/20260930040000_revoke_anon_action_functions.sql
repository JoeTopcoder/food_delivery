-- ============================================================================
-- linter 0028 (anon can execute SECURITY DEFINER) — SAFE SUBSET.
-- Revoke anon EXECUTE from clearly authenticated-only ACTION/mutation functions
-- (a guest is never meant to call these). authenticated + service_role keep
-- access; triggers/other definer functions are unaffected (they run as owner).
--
-- Intentionally NOT touched (to avoid breaking guest browsing / RLS):
--   * get_*  / search_*  read functions (guest-facing feeds, search, config)
--   * _-prefixed internal helpers (used inside RLS policies)
--   * admin_* (already locked in the previous migration)
-- ============================================================================

DO $do$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
    WHERE ns.nspname = 'public'
      AND p.prosecdef
      AND has_function_privilege('anon', p.oid, 'EXECUTE')
      AND (
        p.proname ~ '^(accept|add|adjust|apply|assign|cancel|claim|complete|confirm|create|decline|delete|finalize|increment|mark|redeem|release|reserve|reverse|settle|submit|toggle|unlink|update|use|wallet)_'
        OR p.proname IN ('send_message_secure','get_or_create_conversation','run_decision_engine')
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
    n := n + 1;
  END LOOP;
  RAISE NOTICE 'anon revoked from % action functions', n;
END
$do$;

NOTIFY pgrst, 'reload schema';
