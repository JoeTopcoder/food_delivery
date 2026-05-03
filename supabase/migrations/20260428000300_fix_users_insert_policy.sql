-- Migration: Fix users insert policy to use only WITH CHECK (true)
-- Date: 2026-04-28

DROP POLICY IF EXISTS "Authenticated can insert own user" ON public.users;
DROP POLICY IF EXISTS "Authenticated can insert user" ON public.users;

CREATE POLICY "Authenticated can insert user"
  ON public.users
  FOR INSERT
  TO authenticated
  WITH CHECK (true);
