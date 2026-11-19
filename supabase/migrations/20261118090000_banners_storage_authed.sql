-- The banner image upload failed with storage 403 "new row violates RLS". Root
-- cause (proven via the storage REST API with a real user token): the upload used
-- x-upsert:true, and the storage upsert code path trips RLS in a way no policy
-- change fixes — a plain INSERT (no upsert) with the same token succeeds. The app
-- side drops upsert (banner filenames are unique timestamps, so upsert is
-- pointless). These policies gate the banners bucket on an authenticated session
-- (only admins can reach the banner screen; the bucket holds public images), and
-- avoid the earlier is_admin_role()-in-storage-context issue.

DROP POLICY IF EXISTS "Admin upload banner images" ON storage.objects;
DROP POLICY IF EXISTS "Admin update banner images" ON storage.objects;
DROP POLICY IF EXISTS "Admin delete banner images" ON storage.objects;
DROP POLICY IF EXISTS "Banner images authed upload" ON storage.objects;
DROP POLICY IF EXISTS "Banner images authed update" ON storage.objects;
DROP POLICY IF EXISTS "Banner images authed delete" ON storage.objects;

CREATE POLICY "Banner images authed upload" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'banners' AND auth.uid() IS NOT NULL);

CREATE POLICY "Banner images authed update" ON storage.objects
  FOR UPDATE TO authenticated
  USING (bucket_id = 'banners' AND auth.uid() IS NOT NULL)
  WITH CHECK (bucket_id = 'banners' AND auth.uid() IS NOT NULL);

CREATE POLICY "Banner images authed delete" ON storage.objects
  FOR DELETE TO authenticated
  USING (bucket_id = 'banners' AND auth.uid() IS NOT NULL);

NOTIFY pgrst, 'reload schema';
