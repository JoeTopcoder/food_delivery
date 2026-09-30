-- ============================================================================
-- Fix linter 0011 (function_search_path_mutable) for our OWN public functions.
-- Pins search_path to `public, extensions, pg_temp`:
--   - public:     the app's own tables/functions (unqualified refs keep working)
--   - extensions: pgcrypto / vector / etc. live here on Supabase
--   - pg_temp:    listed LAST so temp objects can't shadow real ones
-- (pg_catalog is always searched implicitly.)
--
-- Excludes extension-owned functions (pg_trgm, vector, …) which we neither own
-- nor should modify, and skips (never fails) any function we lack ownership of.
-- Functions that already pin a search_path are skipped.
-- ============================================================================

DO $do$
DECLARE
  r record;
  done int := 0;
  skipped int := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure::text AS sig
    FROM pg_proc p
    JOIN pg_namespace nsp ON nsp.oid = p.pronamespace
    WHERE nsp.nspname = 'public'
      AND p.prokind = 'f'
      AND NOT EXISTS (
        SELECT 1 FROM unnest(coalesce(p.proconfig, ARRAY[]::text[])) c
        WHERE c ILIKE 'search_path=%'
      )
      -- not owned by an extension (pg_trgm, vector, etc.)
      AND NOT EXISTS (
        SELECT 1 FROM pg_depend d
        WHERE d.classid = 'pg_proc'::regclass
          AND d.objid = p.oid
          AND d.deptype = 'e'
      )
  LOOP
    BEGIN
      EXECUTE format('ALTER FUNCTION %s SET search_path = public, extensions, pg_temp', r.sig);
      done := done + 1;
    EXCEPTION WHEN insufficient_privilege THEN
      skipped := skipped + 1;  -- not our function; leave it alone
    WHEN OTHERS THEN
      skipped := skipped + 1;
    END;
  END LOOP;
  RAISE NOTICE 'search_path pinned on % functions (skipped %)', done, skipped;
END
$do$;

NOTIFY pgrst, 'reload schema';
