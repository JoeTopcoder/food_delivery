-- Allow authenticated users to insert/update their own earning account row
CREATE POLICY IF NOT EXISTS "users_insert_own_earning_account" ON public.earning_accounts
  FOR INSERT TO authenticated WITH CHECK (user_id = auth.uid());

CREATE POLICY IF NOT EXISTS "users_update_own_earning_account" ON public.earning_accounts
  FOR UPDATE TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
