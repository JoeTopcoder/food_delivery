-- ============================================================================
-- HotBite Restaurant Ads — storage buckets + policies
-- ad-assets-raw : PRIVATE. Raw/draft uploads (restaurant or admin). Never served
--                 to customers. Object path convention: "<restaurant_id>/<file>".
-- ad-assets     : PUBLIC. Only APPROVED, processed playback assets live here;
--                 written by admin/service role after approval + processing.
-- ============================================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('ad-assets-raw', 'ad-assets-raw', false)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('ad-assets', 'ad-assets', true)
ON CONFLICT (id) DO NOTHING;

-- ── RAW bucket policies (private, restaurant-scoped by first path segment) ────
-- Managers of the restaurant (owner / active staff) or admins may upload & read
-- their own raw assets. First folder in the object path must be their restaurant id.
DROP POLICY IF EXISTS ad_raw_insert ON storage.objects;
CREATE POLICY ad_raw_insert ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'ad-assets-raw'
    AND public.can_manage_restaurant(NULLIF((storage.foldername(name))[1], '')::uuid)
  );

DROP POLICY IF EXISTS ad_raw_select ON storage.objects;
CREATE POLICY ad_raw_select ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'ad-assets-raw'
    AND public.can_manage_restaurant(NULLIF((storage.foldername(name))[1], '')::uuid)
  );

DROP POLICY IF EXISTS ad_raw_update ON storage.objects;
CREATE POLICY ad_raw_update ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'ad-assets-raw'
         AND public.can_manage_restaurant(NULLIF((storage.foldername(name))[1], '')::uuid));

DROP POLICY IF EXISTS ad_raw_delete ON storage.objects;
CREATE POLICY ad_raw_delete ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'ad-assets-raw'
         AND public.can_manage_restaurant(NULLIF((storage.foldername(name))[1], '')::uuid));

-- ── PUBLIC playback bucket policies ──────────────────────────────────────────
-- Public read (customers). Writes are admin-only (the processing step runs with
-- the service role, which bypasses RLS; this policy covers admin JWT writes).
DROP POLICY IF EXISTS ad_pub_read ON storage.objects;
CREATE POLICY ad_pub_read ON storage.objects FOR SELECT
  USING (bucket_id = 'ad-assets');

DROP POLICY IF EXISTS ad_pub_admin_write ON storage.objects;
CREATE POLICY ad_pub_admin_write ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'ad-assets' AND public.is_admin());

NOTIFY pgrst, 'reload schema';
