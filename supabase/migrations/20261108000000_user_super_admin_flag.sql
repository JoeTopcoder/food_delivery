-- Business-level super-admin flag on public.users. A super admin sees the full
-- admin dashboard; a regular admin (flag false) sees only Orders, Riders,
-- Restaurants and Stores. Seed the existing admin (support@7-dash.com) as super.
BEGIN;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS is_super_admin boolean NOT NULL DEFAULT false;

UPDATE public.users SET is_super_admin = true
WHERE role = 'admin' AND email = 'support@7-dash.com';

-- Resolver used by the app: is the CURRENT user a super admin? SECURITY DEFINER
-- so it works regardless of row-level read policies on users.
CREATE OR REPLACE FUNCTION public.current_user_is_super_admin()
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT is_super_admin FROM public.users WHERE id = auth.uid()),
    false
  );
$$;

GRANT EXECUTE ON FUNCTION public.current_user_is_super_admin() TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
