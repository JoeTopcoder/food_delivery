-- Allow authenticated users to insert their own profile row (social sign-in)
DROP POLICY IF EXISTS "users_insert_own_profile" ON public.users;
CREATE POLICY "users_insert_own_profile"
  ON public.users FOR INSERT
  TO authenticated
  WITH CHECK (id = auth.uid());

-- Allow authenticated users to read their own profile
DROP POLICY IF EXISTS "users_select_own_profile" ON public.users;
CREATE POLICY "users_select_own_profile"
  ON public.users FOR SELECT
  TO authenticated
  USING (id = auth.uid());

-- RPC: create or fetch user profile for social logins (SECURITY DEFINER so it
-- bypasses RLS – needed because upsert with ON CONFLICT requires broader perms).
CREATE OR REPLACE FUNCTION public.ensure_user_profile(
  p_user_id UUID,
  p_email TEXT,
  p_name TEXT,
  p_role TEXT DEFAULT 'user'
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, name, role, is_active, created_at)
  VALUES (p_user_id, p_email, COALESCE(NULLIF(p_name, ''), 'User'), p_role, TRUE, NOW())
  ON CONFLICT (id) DO NOTHING;
END;
$$;
