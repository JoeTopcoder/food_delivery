-- Rollback: undo the three migrations pushed on 2026-04-28 / 2026-04-29
--   * 20260428000100_enable_rls_and_insert_policy_on_users.sql
--   * 20260428000300_fix_users_insert_policy.sql
--   * 20260429000001_fix_role_constraint_allow_user.sql
--
-- Run this in the Supabase SQL editor against the remote project to restore
-- the schema to its pre-2026-04-28 state.
--
-- Note: RLS on public.users was already enabled by migration 093, so we keep
-- it enabled here (we only drop the two new INSERT policies).

BEGIN;

-- 1. Drop INSERT policies added by the two April policy migrations.
DROP POLICY IF EXISTS "Authenticated can insert user" ON public.users;
DROP POLICY IF EXISTS "Authenticated can insert own user" ON public.users;

-- 2. Restore the pre-04-29 role check: users_role_growth_check allowed
--    ('customer', 'driver', 'restaurant', 'admin') after migration 093.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_role_growth_check'
  ) THEN
    ALTER TABLE public.users DROP CONSTRAINT users_role_growth_check;
  END IF;

  -- Convert any rows the rollback migration created back to 'customer'
  UPDATE public.users SET role = 'customer' WHERE role = 'user';

  ALTER TABLE public.users
    ADD CONSTRAINT users_role_growth_check
    CHECK (role IN ('customer', 'driver', 'restaurant', 'admin'));
END $$;

-- 3. Remove the rolled-back migrations from supabase_migrations.schema_migrations
--    so a future `supabase db push` won't think they're applied. Skips silently
--    if that tracking table doesn't exist in your project.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'supabase_migrations' AND table_name = 'schema_migrations'
  ) THEN
    DELETE FROM supabase_migrations.schema_migrations
    WHERE version IN (
      '20260428000100',
      '20260428000300',
      '20260429000001'
    );
  END IF;
END $$;

COMMIT;
