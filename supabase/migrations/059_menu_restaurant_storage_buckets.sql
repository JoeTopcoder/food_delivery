-- Create storage buckets for menu item images and restaurant images
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('menu-images', 'menu-images', true, 5242880, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('restaurant-images', 'restaurant-images', true, 5242880, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

-- Update existing RLS policies to include new buckets
DO $$ BEGIN
  -- Drop and recreate policies to include new buckets
  DROP POLICY IF EXISTS pp_insert ON storage.objects;
  CREATE POLICY pp_insert ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id IN ('profile-photos','review-photos','menu-images','restaurant-images'));

  DROP POLICY IF EXISTS pp_select ON storage.objects;
  CREATE POLICY pp_select ON storage.objects FOR SELECT TO public
    USING (bucket_id IN ('profile-photos','review-photos','menu-images','restaurant-images'));

  DROP POLICY IF EXISTS pp_update ON storage.objects;
  CREATE POLICY pp_update ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id IN ('profile-photos','review-photos','menu-images','restaurant-images'));
END $$;
