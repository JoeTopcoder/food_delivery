-- Restaurant onboarding / verification system
-- Adds submission lifecycle columns to restaurants and creates restaurant_documents table.

-- ── 1. Extend restaurants table ──────────────────────────────────────────────

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS submitted_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reviewed_at       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reviewed_by       UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS approved_at       TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason  TEXT;

-- Widen the status check to include the full lifecycle.
-- Drop old constraint if it exists, then recreate.
DO $$ BEGIN
  ALTER TABLE public.restaurants
    DROP CONSTRAINT IF EXISTS restaurants_status_check;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

ALTER TABLE public.restaurants
  ADD CONSTRAINT restaurants_status_check
    CHECK (status IN ('draft', 'pending_review', 'under_review', 'approved', 'rejected'));

-- ── 2. Restaurant documents table ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.restaurant_documents (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id       UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  document_type       TEXT NOT NULL,   -- 'business_registration' | 'health_permit' | 'food_permit' | 'tax_certificate' | 'other'
  document_number     TEXT,
  photo_url           TEXT,
  expiry_date         DATE,
  verification_status TEXT NOT NULL DEFAULT 'pending',  -- 'pending' | 'approved' | 'rejected'
  rejection_notes     TEXT,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_restaurant_documents_restaurant_id
  ON public.restaurant_documents(restaurant_id);

-- RLS
ALTER TABLE public.restaurant_documents ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "owner_read_own_restaurant_docs"
    ON public.restaurant_documents FOR SELECT
    USING (
      restaurant_id IN (
        SELECT id FROM public.restaurants WHERE owner_id = auth.uid()
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "owner_insert_restaurant_docs"
    ON public.restaurant_documents FOR INSERT
    WITH CHECK (
      restaurant_id IN (
        SELECT id FROM public.restaurants WHERE owner_id = auth.uid()
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "owner_update_restaurant_docs"
    ON public.restaurant_documents FOR UPDATE
    USING (
      restaurant_id IN (
        SELECT id FROM public.restaurants WHERE owner_id = auth.uid()
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "admin_all_restaurant_docs"
    ON public.restaurant_documents FOR ALL
    USING (
      EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 3. Storage bucket for restaurant documents ────────────────────────────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'restaurant-documents',
  'restaurant-documents',
  FALSE,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'restaurant-photos',
  'restaurant-photos',
  TRUE,
  5242880,
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS for restaurant documents (owner can upload to their restaurant folder)
DO $$ BEGIN
  CREATE POLICY "restaurant_docs_upload"
    ON storage.objects FOR INSERT
    WITH CHECK (
      bucket_id = 'restaurant-documents'
      AND (storage.foldername(name))[1] = (
        SELECT id::TEXT FROM public.restaurants WHERE owner_id = auth.uid() LIMIT 1
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "restaurant_docs_read_own"
    ON storage.objects FOR SELECT
    USING (
      bucket_id = 'restaurant-documents'
      AND (storage.foldername(name))[1] = (
        SELECT id::TEXT FROM public.restaurants WHERE owner_id = auth.uid() LIMIT 1
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "restaurant_photos_upload"
    ON storage.objects FOR INSERT
    WITH CHECK (
      bucket_id = 'restaurant-photos'
      AND (storage.foldername(name))[1] = (
        SELECT id::TEXT FROM public.restaurants WHERE owner_id = auth.uid() LIMIT 1
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "admin_restaurant_docs_all"
    ON storage.objects FOR ALL
    USING (
      bucket_id IN ('restaurant-documents', 'restaurant-photos')
      AND EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 4. Update admin_verify_restaurant to set full status ─────────────────────

CREATE OR REPLACE FUNCTION public.admin_verify_restaurant(
  p_restaurant_id UUID,
  p_is_verified   BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_status TEXT;
  v_doc_status TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Unauthorized: admin only';
  END IF;

  v_new_status := CASE WHEN p_is_verified THEN 'approved' ELSE 'rejected' END;
  v_doc_status := CASE WHEN p_is_verified THEN 'approved' ELSE 'rejected' END;

  UPDATE public.restaurants
  SET
    is_verified      = p_is_verified,
    status           = v_new_status,
    approved_at      = CASE WHEN p_is_verified THEN NOW() ELSE NULL END,
    rejection_reason = CASE WHEN p_is_verified THEN NULL ELSE 'Application rejected by admin.' END,
    reviewed_at      = NOW(),
    reviewed_by      = auth.uid(),
    updated_at       = NOW()
  WHERE id = p_restaurant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Restaurant not found';
  END IF;

  -- Also update all document verification statuses
  UPDATE public.restaurant_documents
  SET verification_status = v_doc_status, updated_at = NOW()
  WHERE restaurant_id = p_restaurant_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_verify_restaurant(UUID, BOOLEAN) TO authenticated;
