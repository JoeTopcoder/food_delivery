-- Banner management was blocked for admins whose session was at aal1 (2FA not
-- applied this session). The inconsistency: the banner IMAGE UPLOAD policy on
-- storage.objects only requires role='admin' (no aal2), so an admin can already
-- upload the banner creative at aal1 — but the banners TABLE insert/update/delete
-- required is_admin() (aal2), so the row write was rejected after the image
-- uploaded. Requiring 2FA on only the row (not the image) adds little security
-- while making banner management fail confusingly.
--
-- Fix: gate banner table writes on admin ROLE only (matching the image policy).
-- Banners are public promotional content with no financial/PII sensitivity. All
-- other admin surfaces keep the stricter aal2 is_admin() check.

-- Role-only admin check (no MFA/aal2 requirement).
CREATE OR REPLACE FUNCTION public.is_admin_role()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

REVOKE ALL ON FUNCTION public.is_admin_role() FROM public;
GRANT EXECUTE ON FUNCTION public.is_admin_role() TO authenticated, service_role;

-- Repoint the banner write policies to the role-only check.
DROP POLICY IF EXISTS banners_admin_insert ON public.banners;
DROP POLICY IF EXISTS banners_admin_update ON public.banners;
DROP POLICY IF EXISTS banners_admin_delete ON public.banners;

CREATE POLICY banners_admin_insert ON public.banners
  FOR INSERT TO authenticated
  WITH CHECK (public.is_admin_role());

CREATE POLICY banners_admin_update ON public.banners
  FOR UPDATE TO authenticated
  USING (public.is_admin_role())
  WITH CHECK (public.is_admin_role());

CREATE POLICY banners_admin_delete ON public.banners
  FOR DELETE TO authenticated
  USING (public.is_admin_role());

-- NOTE: a banner WITH a discount also writes promo_codes (money-sensitive), which
-- keeps the stricter aal2 is_admin() check. So a *discount* banner still needs a
-- 2FA session; a plain promotional banner (no discount) now works at admin role.

NOTIFY pgrst, 'reload schema';
