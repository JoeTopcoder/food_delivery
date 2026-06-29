-- =============================================================================
-- LOAD TEST USER CLEANUP  —  cleanup-load-test-users.sql
-- Deletes ONLY the 200 synthetic load test accounts.
-- Real user data is untouched.
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → paste this file → Run
-- =============================================================================

DO $$
DECLARE
  v_deleted_auth   INTEGER := 0;
  v_deleted_public INTEGER := 0;
  v_id             UUID;
BEGIN

  -- 1. Delete from auth.users (cascade deletes public.users via trigger/FK)
  FOR v_id IN
    SELECT id FROM auth.users
    WHERE email LIKE 'loadtest\_%@test.mealhub.dev' ESCAPE '\'
  LOOP
    DELETE FROM auth.users WHERE id = v_id;
    v_deleted_auth := v_deleted_auth + 1;
  END LOOP;

  -- 2. Belt-and-suspenders: also clean public.users in case any rows were
  --    orphaned (e.g. created before the FK cascade was added).
  DELETE FROM public.users
  WHERE email LIKE 'loadtest\_%@test.mealhub.dev' ESCAPE '\';

  GET DIAGNOSTICS v_deleted_public = ROW_COUNT;

  RAISE NOTICE 'Deleted % auth.users rows and % orphaned public.users rows.',
               v_deleted_auth, v_deleted_public;
END $$;
