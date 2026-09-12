-- Migration: school lunch ordering — schools, students, parent links
--
-- Built on what already exists rather than beside it:
--   * A student IS a users row with their own wallet, so parents link them by
--     the same wallet ID the wallet-transfer feature already resolves
--     (referral_code, else the first six hex characters of the UUID).
--   * Lunch providers are restaurants with store_type 'lunch', so menus,
--     pricing, cart and checkout all work unchanged.
--   * Orders stay in the orders table with lunch fields added.
--
-- The cart deliberately holds NO recipient. Who the lunch is for is decided at
-- checkout, so the same cart can be sent to a child or kept for yourself.

CREATE TABLE IF NOT EXISTS public.schools (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT NOT NULL,
  address    TEXT NOT NULL,
  city       TEXT,
  latitude   DOUBLE PRECISION,
  longitude  DOUBLE PRECISION,
  is_active  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- A student's school. Separate from users so a non-student account carries no
-- school columns, and so the row can be extended (grade, homeroom) later.
CREATE TABLE IF NOT EXISTS public.student_profiles (
  user_id    UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  school_id  UUID REFERENCES public.schools(id) ON DELETE SET NULL,
  grade      TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.parent_student_links (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  student_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  -- 'active' can order; 'revoked' keeps the history without the permission.
  status     TEXT NOT NULL DEFAULT 'active'
             CHECK (status IN ('active', 'revoked')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (parent_id, student_id),
  CONSTRAINT parent_is_not_student CHECK (parent_id <> student_id)
);

CREATE INDEX IF NOT EXISTS idx_parent_links_parent
  ON public.parent_student_links (parent_id) WHERE status = 'active';

ALTER TABLE public.schools              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.student_profiles     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.parent_student_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS schools_readable ON public.schools;
CREATE POLICY schools_readable ON public.schools FOR SELECT USING (is_active);

-- A student's school is visible to the student and to a parent linked to them.
DROP POLICY IF EXISTS student_profiles_visible ON public.student_profiles;
CREATE POLICY student_profiles_visible ON public.student_profiles FOR SELECT
USING (
  user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.parent_student_links l
    WHERE l.student_id = student_profiles.user_id
      AND l.parent_id = auth.uid()
      AND l.status = 'active'
  )
);

-- Either side of a link can see it; only the parent creates one, and only for
-- themselves — the parent_id can never be someone else.
DROP POLICY IF EXISTS links_visible ON public.parent_student_links;
CREATE POLICY links_visible ON public.parent_student_links FOR SELECT
USING (parent_id = auth.uid() OR student_id = auth.uid());

DROP POLICY IF EXISTS links_insert_own ON public.parent_student_links;
CREATE POLICY links_insert_own ON public.parent_student_links FOR INSERT
WITH CHECK (parent_id = auth.uid());

DROP POLICY IF EXISTS links_update_own ON public.parent_student_links;
CREATE POLICY links_update_own ON public.parent_student_links FOR UPDATE
USING (parent_id = auth.uid()) WITH CHECK (parent_id = auth.uid());

-- ── Lunch fields on orders ─────────────────────────────────────────────────
-- School name and address are SNAPSHOTTED, not looked up when the order is
-- displayed: a student can change school, and an old order must still show
-- where the food was actually sent.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS recipient_type   TEXT
    CHECK (recipient_type IS NULL OR recipient_type IN ('self','student')),
  ADD COLUMN IF NOT EXISTS student_id       UUID REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS school_id        UUID REFERENCES public.schools(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS school_name      TEXT,
  ADD COLUMN IF NOT EXISTS school_address   TEXT;

COMMENT ON COLUMN public.orders.school_name IS
  'Snapshot at order time. Never re-read from the student''s current school — '
  'they may have moved, and the order must still show where it was sent.';

-- Lunch delivery fees, configurable like every other fee.
INSERT INTO public.app_config (key, value, description) VALUES
  ('lunch_delivery_fee_self',    '900', 'Lunch delivery fee (JMD) when ordering for yourself.'),
  ('lunch_delivery_fee_student', '350', 'Lunch delivery fee (JMD) when delivering to a linked student at school.')
ON CONFLICT (key) DO NOTHING;

NOTIFY pgrst, 'reload schema';
