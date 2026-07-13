-- ─────────────────────────────────────────────────────────────────────────────
-- The `banners` storage bucket was never created, so every banner-image
-- upload from admin_banners_screen.dart failed with a "bucket not found"
-- 404, surfaced to the admin as the generic "requested item was not found."
-- Same admin-write / public-read shape as the existing category-images
-- bucket (banners are admin-managed, no per-user folder scoping needed).
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO storage.buckets (id, name, public)
VALUES ('banners', 'banners', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Admin upload banner images"
ON storage.objects FOR INSERT
WITH CHECK (
  bucket_id = 'banners'
  AND EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'admin')
);

CREATE POLICY "Admin update banner images"
ON storage.objects FOR UPDATE
USING (
  bucket_id = 'banners'
  AND EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'admin')
);

CREATE POLICY "Public read banner images"
ON storage.objects FOR SELECT
USING (bucket_id = 'banners');
