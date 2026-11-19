-- Make the banners bucket upload/update policies use the SECURITY DEFINER
-- is_admin_role() function (same as the banners table), instead of an inline
-- EXISTS over public.users. The inline subquery runs as the authenticated role
-- inside the storage RLS context (its own search_path / grants), which is a
-- known source of subtle failures; the SECURITY DEFINER function evaluates the
-- admin check consistently regardless of that context. Role-only (no aal2),
-- matching the banners table write policies.

DROP POLICY IF EXISTS "Admin upload banner images" ON storage.objects;
DROP POLICY IF EXISTS "Admin update banner images" ON storage.objects;

CREATE POLICY "Admin upload banner images" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'banners' AND public.is_admin_role());

CREATE POLICY "Admin update banner images" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'banners' AND public.is_admin_role())
  WITH CHECK (bucket_id = 'banners' AND public.is_admin_role());

NOTIFY pgrst, 'reload schema';
