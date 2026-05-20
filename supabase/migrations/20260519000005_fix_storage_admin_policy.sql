-- Fix: replace the driver-documents storage admin policy to use is_admin()
-- instead of a sub-query on public.users. This avoids any potential
-- query-plan issues and makes the policy consistent with the table policies.

DROP POLICY IF EXISTS "admin_driver_docs_all" ON storage.objects;

CREATE POLICY "admin_driver_docs_all"
  ON storage.objects FOR ALL
  USING (
    bucket_id IN ('driver-documents', 'driver-profile-photos')
    AND is_admin()
  );
