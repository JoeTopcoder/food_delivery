-- Allow authenticated users to insert/update their own earning account row
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'earning_accounts'
    AND policyname = 'users_insert_own_earning_account'
  ) THEN
    CREATE POLICY "users_insert_own_earning_account" ON public.earning_accounts
      FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'earning_accounts'
    AND policyname = 'users_update_own_earning_account'
  ) THEN
    CREATE POLICY "users_update_own_earning_account" ON public.earning_accounts
      FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
  END IF;
END
$$;
