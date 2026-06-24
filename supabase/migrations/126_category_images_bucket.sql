-- ── 126_category_images_bucket ───────────────────────────────────────────────
-- Public storage bucket for category images (food & grocery).
-- Admins upload via the admin categories screen; URLs are stored in the
-- food_categories and grocery_categories tables.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'category-images',
  'category-images',
  true,
  5242880,   -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Anyone can view (bucket is public)
CREATE POLICY "Public read category images"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'category-images');

-- Only admins can upload / replace
CREATE POLICY "Admin upload category images"
  ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'category-images'
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Admin update category images"
  ON storage.objects FOR UPDATE
  USING (
    bucket_id = 'category-images'
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY "Admin delete category images"
  ON storage.objects FOR DELETE
  USING (
    bucket_id = 'category-images'
    AND EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );
