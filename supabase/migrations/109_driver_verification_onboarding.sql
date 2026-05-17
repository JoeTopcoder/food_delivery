-- ============================================================
-- Migration 109: Driver Verification & Onboarding System
-- Extends the EXISTING drivers table and adds supporting tables.
-- All ALTER TABLE statements use ADD COLUMN IF NOT EXISTS (safe for production).
-- ============================================================

-- ── 1. Extend existing drivers table ──────────────────────────────────────────

ALTER TABLE public.drivers
  -- Verification lifecycle
  ADD COLUMN IF NOT EXISTS driver_status TEXT NOT NULL DEFAULT 'draft'
    CHECK (driver_status IN ('draft', 'pending_review', 'under_review', 'approved', 'rejected', 'suspended', 'expired_documents')),
  ADD COLUMN IF NOT EXISTS onboarding_step INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS submitted_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS reviewed_by UUID REFERENCES auth.users(id),
  ADD COLUMN IF NOT EXISTS reviewed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS rejection_reason TEXT,

  -- Service type selection
  ADD COLUMN IF NOT EXISTS service_type TEXT NOT NULL DEFAULT 'food_delivery'
    CHECK (service_type IN ('food_delivery', 'ride_sharing', 'both')),

  -- Personal info cached on driver row for fast admin queries (source of truth stays in users)
  ADD COLUMN IF NOT EXISTS full_name TEXT,
  ADD COLUMN IF NOT EXISTS phone_number TEXT,
  ADD COLUMN IF NOT EXISTS profile_photo_url TEXT,
  ADD COLUMN IF NOT EXISTS date_of_birth DATE,
  ADD COLUMN IF NOT EXISTS home_address TEXT,

  -- Per-service approval flags (is_ride_driver_approved already referenced by find-nearby-drivers)
  ADD COLUMN IF NOT EXISTS is_food_driver_approved BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_ride_driver_approved BOOLEAN NOT NULL DEFAULT FALSE,

  -- Live availability per service
  ADD COLUMN IF NOT EXISTS is_available_for_food BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS is_available_for_rides BOOLEAN NOT NULL DEFAULT FALSE,

  -- Overall online/offline toggle (driver goes "on duty")
  ADD COLUMN IF NOT EXISTS is_online BOOLEAN NOT NULL DEFAULT FALSE;

-- ── 2. driver_identity_documents ──────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.driver_identity_documents (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id           UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  document_type       TEXT NOT NULL
    CHECK (document_type IN ('national_id', 'passport', 'driving_permit', 'voters_id', 'other')),
  document_number     TEXT,
  front_photo_url     TEXT,
  back_photo_url      TEXT,
  expiry_date         DATE,
  verification_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN ('pending', 'approved', 'rejected', 'expired')),
  rejection_notes     TEXT,
  verified_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.driver_identity_documents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "driver_identity_docs_own_read"
  ON public.driver_identity_documents FOR SELECT
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "driver_identity_docs_own_write"
  ON public.driver_identity_documents FOR INSERT
  WITH CHECK (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "driver_identity_docs_own_update"
  ON public.driver_identity_documents FOR UPDATE
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "admin_identity_docs_all"
  ON public.driver_identity_documents FOR ALL
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

-- ── 3. driver_licenses ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.driver_licenses (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id           UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  license_number      TEXT,
  license_class       TEXT,
  issue_date          DATE,
  expiry_date         DATE,
  front_photo_url     TEXT,
  back_photo_url      TEXT,
  verification_status TEXT NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN ('pending', 'approved', 'rejected', 'expired')),
  rejection_notes     TEXT,
  verified_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.driver_licenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "driver_licenses_own_read"
  ON public.driver_licenses FOR SELECT
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "driver_licenses_own_write"
  ON public.driver_licenses FOR INSERT
  WITH CHECK (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "driver_licenses_own_update"
  ON public.driver_licenses FOR UPDATE
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "admin_licenses_all"
  ON public.driver_licenses FOR ALL
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

-- ── 4. driver_vehicles ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.driver_vehicles (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id               UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  vehicle_type            TEXT NOT NULL DEFAULT 'motorcycle'
    CHECK (vehicle_type IN ('bicycle', 'motorcycle', 'scooter', 'car', 'van', 'truck')),
  make                    TEXT,
  model                   TEXT,
  year                    INTEGER,
  color                   TEXT,
  license_plate           TEXT,
  vin                     TEXT,
  registration_photo_url  TEXT,
  is_primary              BOOLEAN NOT NULL DEFAULT TRUE,
  verification_status     TEXT NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN ('pending', 'approved', 'rejected', 'expired')),
  rejection_notes         TEXT,
  verified_at             TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.driver_vehicles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "driver_vehicles_own_read"
  ON public.driver_vehicles FOR SELECT
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "driver_vehicles_own_write"
  ON public.driver_vehicles FOR INSERT
  WITH CHECK (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "driver_vehicles_own_update"
  ON public.driver_vehicles FOR UPDATE
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "admin_vehicles_all"
  ON public.driver_vehicles FOR ALL
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

-- ── 5. driver_insurance ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.driver_insurance (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id             UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  insurance_provider    TEXT,
  policy_number         TEXT,
  coverage_type         TEXT DEFAULT 'third_party',
  coverage_amount       NUMERIC(12, 2),
  expiry_date           DATE,
  document_photo_url    TEXT,
  verification_status   TEXT NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN ('pending', 'approved', 'rejected', 'expired')),
  rejection_notes       TEXT,
  verified_at           TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.driver_insurance ENABLE ROW LEVEL SECURITY;

CREATE POLICY "driver_insurance_own_read"
  ON public.driver_insurance FOR SELECT
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "driver_insurance_own_write"
  ON public.driver_insurance FOR INSERT
  WITH CHECK (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "driver_insurance_own_update"
  ON public.driver_insurance FOR UPDATE
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "admin_insurance_all"
  ON public.driver_insurance FOR ALL
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

-- ── 6. driver_consents ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.driver_consents (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id     UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  consent_type  TEXT NOT NULL
    CHECK (consent_type IN ('terms_of_service', 'privacy_policy', 'background_check', 'data_sharing', 'insurance_disclosure')),
  consented     BOOLEAN NOT NULL DEFAULT FALSE,
  consented_at  TIMESTAMPTZ,
  app_version   TEXT,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (driver_id, consent_type)
);

ALTER TABLE public.driver_consents ENABLE ROW LEVEL SECURITY;

CREATE POLICY "driver_consents_own_read"
  ON public.driver_consents FOR SELECT
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "driver_consents_own_write"
  ON public.driver_consents FOR INSERT
  WITH CHECK (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "driver_consents_own_update"
  ON public.driver_consents FOR UPDATE
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "admin_consents_all"
  ON public.driver_consents FOR ALL
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

-- ── 7. driver_verification_logs ───────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.driver_verification_logs (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id   UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  action      TEXT NOT NULL,
  actor_id    UUID REFERENCES auth.users(id),
  old_status  TEXT,
  new_status  TEXT,
  notes       TEXT,
  metadata    JSONB,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.driver_verification_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "driver_logs_own_read"
  ON public.driver_verification_logs FOR SELECT
  USING (driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1));

CREATE POLICY "admin_logs_all"
  ON public.driver_verification_logs FOR ALL
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

-- ── 8. Storage bucket for driver documents ───────────────────────────────────

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'driver-documents',
  'driver-documents',
  FALSE,
  10485760, -- 10 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'driver-profile-photos',
  'driver-profile-photos',
  TRUE,
  5242880, -- 5 MB
  ARRAY['image/jpeg', 'image/png', 'image/webp']
)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: drivers can upload to their own folder (driver_id/filename)
DO $$ BEGIN
  CREATE POLICY "driver_docs_upload"
    ON storage.objects FOR INSERT
    WITH CHECK (
      bucket_id = 'driver-documents'
      AND (storage.foldername(name))[1] = (
        SELECT id::TEXT FROM public.drivers WHERE user_id = auth.uid() LIMIT 1
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "driver_docs_read_own"
    ON storage.objects FOR SELECT
    USING (
      bucket_id = 'driver-documents'
      AND (storage.foldername(name))[1] = (
        SELECT id::TEXT FROM public.drivers WHERE user_id = auth.uid() LIMIT 1
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "admin_driver_docs_all"
    ON storage.objects FOR ALL
    USING (
      bucket_id IN ('driver-documents', 'driver-profile-photos')
      AND EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE POLICY "driver_profile_photos_upload"
    ON storage.objects FOR INSERT
    WITH CHECK (
      bucket_id = 'driver-profile-photos'
      AND (storage.foldername(name))[1] = (
        SELECT id::TEXT FROM public.drivers WHERE user_id = auth.uid() LIMIT 1
      )
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ── 9. Indexes for common queries ─────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_drivers_driver_status ON public.drivers(driver_status);
CREATE INDEX IF NOT EXISTS idx_drivers_is_online ON public.drivers(is_online);
CREATE INDEX IF NOT EXISTS idx_drivers_service_type ON public.drivers(service_type);
CREATE INDEX IF NOT EXISTS idx_driver_identity_docs_driver_id ON public.driver_identity_documents(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_licenses_driver_id ON public.driver_licenses(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_vehicles_driver_id ON public.driver_vehicles(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_insurance_driver_id ON public.driver_insurance(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_consents_driver_id ON public.driver_consents(driver_id);
CREATE INDEX IF NOT EXISTS idx_driver_verification_logs_driver_id ON public.driver_verification_logs(driver_id);

-- ── 10. Helper function: log a verification action ────────────────────────────

CREATE OR REPLACE FUNCTION public.log_driver_verification(
  p_driver_id UUID,
  p_action    TEXT,
  p_actor_id  UUID,
  p_old_status TEXT DEFAULT NULL,
  p_new_status TEXT DEFAULT NULL,
  p_notes     TEXT DEFAULT NULL,
  p_metadata  JSONB DEFAULT NULL
) RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.driver_verification_logs
    (driver_id, action, actor_id, old_status, new_status, notes, metadata)
  VALUES
    (p_driver_id, p_action, p_actor_id, p_old_status, p_new_status, p_notes, p_metadata);
END;
$$;
