-- ════════════════════════════════════════════════════════════════════════════
-- Student ID verification — schema, storage, RLS, audit (Phase 2/3/18/19).
--
-- Integrates with the EXISTING school-lunch system (migrations 20260907000006+):
--   • schools               → the participating-school list (is_active = eligible)
--   • student_profiles      → a student is a users row + school
--   • parent_student_links  → parent ↔ student
--   • orders.recipient_type='student', student_id, school_id, school_name/address
-- Nothing existing is replaced. This adds the verification/benefits/driver-review
-- layer on top. All privileged status changes happen through SECURITY DEFINER
-- RPCs (next migration) — clients never write verification_status/benefits_active.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Extend the existing schools list (do NOT create participating_schools) ─
ALTER TABLE public.schools
  ADD COLUMN IF NOT EXISTS school_code TEXT,
  ADD COLUMN IF NOT EXISTS updated_at  TIMESTAMPTZ NOT NULL DEFAULT now();

-- ── 2. Verification attempts (history kept: many rows per student) ───────────
CREATE TABLE IF NOT EXISTS public.student_verifications (
  id                       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  student_name             TEXT,
  student_id_number        TEXT,
  school_id                UUID REFERENCES public.schools(id) ON DELETE SET NULL,
  submitted_selfie_url     TEXT,
  student_id_image_url     TEXT,
  extracted_name           TEXT,
  extracted_student_id     TEXT,
  extracted_school         TEXT,
  extracted_issue_date     DATE,
  extracted_expiration_date DATE,
  extracted_document_number TEXT,
  ocr_confidence           NUMERIC,
  name_match               BOOLEAN,
  student_id_match         BOOLEAN,
  school_match             BOOLEAN,
  expiration_valid         BOOLEAN,
  verification_status      TEXT NOT NULL DEFAULT 'pending'
    CHECK (verification_status IN
      ('pending','processing','approved','needs_update','manual_review',
       'rejected','expired','suspended')),
  benefits_active          BOOLEAN NOT NULL DEFAULT FALSE,
  rejection_reason         TEXT,
  review_reason            TEXT,
  verified_at              TIMESTAMPTZ,
  expires_at               TIMESTAMPTZ,
  created_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at               TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_student_verifications_user
  ON public.student_verifications (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_student_verifications_expiry
  ON public.student_verifications (expires_at)
  WHERE verification_status = 'approved' AND benefits_active = TRUE;

-- ── 3. Driver school-delivery confirmations (one per order) ──────────────────
CREATE TABLE IF NOT EXISTS public.student_delivery_confirmations (
  id                 UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id           UUID NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
  student_id         UUID REFERENCES public.users(id) ON DELETE SET NULL,
  school_id          UUID REFERENCES public.schools(id) ON DELETE SET NULL,
  driver_id          UUID REFERENCES public.users(id) ON DELETE SET NULL,
  delivery_confirmed BOOLEAN NOT NULL,
  reason             TEXT,
  confirmed_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── 4. Company review queue for "not delivered at school" reports ────────────
CREATE TABLE IF NOT EXISTS public.student_delivery_reviews (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id    UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  student_id  UUID REFERENCES public.users(id) ON DELETE SET NULL,
  school_id   UUID REFERENCES public.schools(id) ON DELETE SET NULL,
  driver_id   UUID REFERENCES public.users(id) ON DELETE SET NULL,
  reason      TEXT,
  status      TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','confirmed_issue','resolved','kept_suspended')),
  admin_notes TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  resolved_at TIMESTAMPTZ,
  resolved_by UUID REFERENCES public.users(id) ON DELETE SET NULL
);
CREATE INDEX IF NOT EXISTS idx_student_delivery_reviews_status
  ON public.student_delivery_reviews (status, created_at DESC);

-- ── 5. Append-only audit log ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.student_verification_audit (
  id         BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  student_id UUID REFERENCES public.users(id) ON DELETE SET NULL,
  actor_id   UUID REFERENCES public.users(id) ON DELETE SET NULL,
  actor_type TEXT,   -- student | parent | driver | admin | system
  action     TEXT NOT NULL,
  old_status TEXT,
  new_status TEXT,
  reason     TEXT,
  metadata   JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_student_audit_student
  ON public.student_verification_audit (student_id, created_at DESC);

-- ── 6. Config: OCR confidence threshold ──────────────────────────────────────
INSERT INTO public.app_config (key, value, description) VALUES
  ('student_ocr_confidence_threshold', '60',
   'Minimum OCR confidence (0-100) required to auto-approve a student ID.')
ON CONFLICT (key) DO NOTHING;

-- ── 7. RLS ───────────────────────────────────────────────────────────────────
ALTER TABLE public.student_verifications          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_delivery_confirmations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_delivery_reviews       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_verification_audit     ENABLE ROW LEVEL SECURITY;

-- Verifications: the student, a linked active parent, or an admin may READ.
-- No client INSERT/UPDATE/DELETE — every write goes through a SECURITY DEFINER
-- RPC, so verification_status / benefits_active can never be set by a client.
DROP POLICY IF EXISTS student_verifications_read ON public.student_verifications;
CREATE POLICY student_verifications_read ON public.student_verifications
  FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.current_user_is_admin()
    OR EXISTS (
      SELECT 1 FROM public.parent_student_links l
      WHERE l.student_id = student_verifications.user_id
        AND l.parent_id = auth.uid() AND l.status = 'active')
  );

-- Confirmations: admin reads all; the assigned driver reads their own rows.
DROP POLICY IF EXISTS student_delivery_confirmations_read ON public.student_delivery_confirmations;
CREATE POLICY student_delivery_confirmations_read ON public.student_delivery_confirmations
  FOR SELECT TO authenticated
  USING (public.current_user_is_admin() OR driver_id = auth.uid());

-- Reviews: admin only (never expose driver/admin internals to students/drivers).
DROP POLICY IF EXISTS student_delivery_reviews_read ON public.student_delivery_reviews;
CREATE POLICY student_delivery_reviews_read ON public.student_delivery_reviews
  FOR SELECT TO authenticated
  USING (public.current_user_is_admin());

-- Audit: the student/linked parent see their own trail; admin sees all.
DROP POLICY IF EXISTS student_verification_audit_read ON public.student_verification_audit;
CREATE POLICY student_verification_audit_read ON public.student_verification_audit
  FOR SELECT TO authenticated
  USING (
    student_id = auth.uid()
    OR public.current_user_is_admin()
    OR EXISTS (
      SELECT 1 FROM public.parent_student_links l
      WHERE l.student_id = student_verification_audit.student_id
        AND l.parent_id = auth.uid() AND l.status = 'active')
  );

-- ── 8. Private storage bucket for ID images + selfies ────────────────────────
INSERT INTO storage.buckets (id, name, public)
VALUES ('student-ids', 'student-ids', FALSE)
ON CONFLICT (id) DO NOTHING;

-- Objects are stored under "<user_id>/...". A user may read/write only their own
-- prefix; admins may read all; drivers get NO access to ID images.
DROP POLICY IF EXISTS student_ids_owner_rw ON storage.objects;
CREATE POLICY student_ids_owner_rw ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id = 'student-ids'
    AND (
      (storage.foldername(name))[1] = auth.uid()::text
      OR public.current_user_is_admin()
    )
  )
  WITH CHECK (
    bucket_id = 'student-ids'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

NOTIFY pgrst, 'reload schema';
