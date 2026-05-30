-- Migration 115: Public storage bucket for banner images
-- Admins upload banner images; everyone can read them publicly.

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'banners',
  'banners',
  true,
  10485760,  -- 10 MB
  ARRAY['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Admins can upload / replace banner images
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'banners_admin_insert' AND tablename = 'objects' AND schemaname = 'storage'
  ) THEN
    CREATE POLICY "banners_admin_insert" ON storage.objects
      FOR INSERT TO authenticated
      WITH CHECK (
        bucket_id = 'banners'
        AND EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'banners_admin_update' AND tablename = 'objects' AND schemaname = 'storage'
  ) THEN
    CREATE POLICY "banners_admin_update" ON storage.objects
      FOR UPDATE TO authenticated
      USING (
        bucket_id = 'banners'
        AND EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
      );
  END IF;

  -- Public read (bucket is public but explicit policy satisfies strict setups)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE policyname = 'banners_public_select' AND tablename = 'objects' AND schemaname = 'storage'
  ) THEN
    CREATE POLICY "banners_public_select" ON storage.objects
      FOR SELECT TO public
      USING (bucket_id = 'banners');
  END IF;
END $$;
