-- Create storage buckets for profile photos and review photos
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('profile-photos', 'profile-photos', true, 5242880, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('review-photos', 'review-photos', true, 5242880, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO NOTHING;

-- RLS policies for storage
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='pp_insert' AND tablename='objects' AND schemaname='storage') THEN
    CREATE POLICY pp_insert ON storage.objects FOR INSERT TO authenticated
      WITH CHECK (bucket_id IN ('profile-photos','review-photos'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='pp_select' AND tablename='objects' AND schemaname='storage') THEN
    CREATE POLICY pp_select ON storage.objects FOR SELECT TO public
      USING (bucket_id IN ('profile-photos','review-photos'));
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='pp_update' AND tablename='objects' AND schemaname='storage') THEN
    CREATE POLICY pp_update ON storage.objects FOR UPDATE TO authenticated
      USING (bucket_id IN ('profile-photos','review-photos'));
  END IF;
END $$;
