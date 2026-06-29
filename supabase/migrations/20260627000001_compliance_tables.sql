-- ─────────────────────────────────────────────────────────────────────────────
-- Compliance Tables: support_requests, user_deletion_requests, chat_reports
-- Required for App Store and Google Play compliance
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Support Requests ──────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.support_requests (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  name        text NOT NULL,
  email       text NOT NULL,
  category    text NOT NULL,
  message     text NOT NULL,
  order_id    text,
  status      text NOT NULL DEFAULT 'open'
                CHECK (status IN ('open', 'reviewing', 'resolved')),
  admin_notes text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.support_requests ENABLE ROW LEVEL SECURITY;

-- Users can insert their own support request (logged in or guest with null user_id)
CREATE POLICY "support_requests_insert_own"
  ON public.support_requests FOR INSERT
  WITH CHECK (
    auth.uid() IS NULL          -- unauthenticated / public form
    OR user_id = auth.uid()     -- authenticated user
  );

-- Users can read only their own requests
CREATE POLICY "support_requests_select_own"
  ON public.support_requests FOR SELECT
  USING (user_id = auth.uid());

-- Admin can read all
CREATE POLICY "support_requests_select_admin"
  ON public.support_requests FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

-- Admin can update (change status, add notes)
CREATE POLICY "support_requests_update_admin"
  ON public.support_requests FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS support_requests_updated_at ON public.support_requests;
CREATE TRIGGER support_requests_updated_at
  BEFORE UPDATE ON public.support_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── User Deletion Requests ────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.user_deletion_requests (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  email        text NOT NULL,
  reason       text,
  status       text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'reviewing', 'processed')),
  admin_notes  text,
  requested_at timestamptz NOT NULL DEFAULT now(),
  processed_at timestamptz
);

ALTER TABLE public.user_deletion_requests ENABLE ROW LEVEL SECURITY;

-- Anyone (logged in or not) can submit a deletion request
CREATE POLICY "deletion_requests_insert_public"
  ON public.user_deletion_requests FOR INSERT
  WITH CHECK (true);

-- Users can view their own requests
CREATE POLICY "deletion_requests_select_own"
  ON public.user_deletion_requests FOR SELECT
  USING (user_id = auth.uid());

-- Admin can read all
CREATE POLICY "deletion_requests_select_admin"
  ON public.user_deletion_requests FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

-- Admin can update (change status, add notes, set processed_at)
CREATE POLICY "deletion_requests_update_admin"
  ON public.user_deletion_requests FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

-- ── Chat / User Reports ───────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.chat_reports (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id      uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reported_user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  message_id       uuid,
  order_id         uuid,
  reason           text NOT NULL,
  details          text,
  status           text NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open', 'reviewing', 'resolved')),
  created_at       timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.chat_reports ENABLE ROW LEVEL SECURITY;

-- Authenticated users can submit a report
CREATE POLICY "chat_reports_insert_auth"
  ON public.chat_reports FOR INSERT
  WITH CHECK (reporter_id = auth.uid());

-- Users cannot read reports (privacy — they can only submit)
-- Admin can read all
CREATE POLICY "chat_reports_select_admin"
  ON public.chat_reports FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

-- Admin can update status
CREATE POLICY "chat_reports_update_admin"
  ON public.chat_reports FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

-- ── Indexes ───────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_support_requests_user_id
  ON public.support_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_support_requests_status
  ON public.support_requests(status);
CREATE INDEX IF NOT EXISTS idx_support_requests_created_at
  ON public.support_requests(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_deletion_requests_user_id
  ON public.user_deletion_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_deletion_requests_status
  ON public.user_deletion_requests(status);
CREATE INDEX IF NOT EXISTS idx_deletion_requests_email
  ON public.user_deletion_requests(email);

CREATE INDEX IF NOT EXISTS idx_chat_reports_reporter_id
  ON public.chat_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_chat_reports_status
  ON public.chat_reports(status);

-- ── Reviewer Demo Account ─────────────────────────────────────────────────────
-- NOTE: Create reviewer@7dash.app in Supabase Auth dashboard (Authentication →
-- Users → Invite user) and assign role 'user' or 'customer'. Do NOT automate
-- this in SQL to avoid leaking credentials in migration history.
-- Password: Review123!
-- This account should bypass OTP flows if you use email confirmations.
-- In Supabase: Authentication → Email → Disable "Confirm email" for this env,
-- or manually confirm the reviewer account in the Auth dashboard.
