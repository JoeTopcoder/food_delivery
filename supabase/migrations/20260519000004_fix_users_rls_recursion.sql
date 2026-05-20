-- Fix: infinite recursion in users RLS policy
-- The "admin_select_all_users_for_driver_join" policy created in migration 003
-- queries public.users from within a policy ON public.users → infinite recursion.
-- Drop it and replace with a SECURITY DEFINER helper that bypasses RLS.

-- Drop the broken self-referential policy
DROP POLICY IF EXISTS "admin_select_all_users_for_driver_join" ON public.users;

-- Create a SECURITY DEFINER function so admin-role checks never trigger
-- the users SELECT policy (avoids the recursion entirely).
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
  );
$$;
