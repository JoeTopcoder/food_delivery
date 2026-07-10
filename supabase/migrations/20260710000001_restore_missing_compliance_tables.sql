-- ─────────────────────────────────────────────────────────────────────────────
-- Restore support_requests and chat_reports, which existed in migration
-- 20260627000001_compliance_tables.sql but are missing from production
-- (user_deletion_requests from the same migration survived intact).
-- Idempotent — safe to run even if the tables already exist.
-- ─────────────────────────────────────────────────────────────────────────────

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

DROP POLICY IF EXISTS "support_requests_insert_own" ON public.support_requests;
CREATE POLICY "support_requests_insert_own"
  ON public.support_requests FOR INSERT
  WITH CHECK (
    auth.uid() IS NULL
    OR user_id = auth.uid()
  );

DROP POLICY IF EXISTS "support_requests_select_own" ON public.support_requests;
CREATE POLICY "support_requests_select_own"
  ON public.support_requests FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "support_requests_select_admin" ON public.support_requests;
CREATE POLICY "support_requests_select_admin"
  ON public.support_requests FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "support_requests_update_admin" ON public.support_requests;
CREATE POLICY "support_requests_update_admin"
  ON public.support_requests FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

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

DROP POLICY IF EXISTS "chat_reports_insert_auth" ON public.chat_reports;
CREATE POLICY "chat_reports_insert_auth"
  ON public.chat_reports FOR INSERT
  WITH CHECK (reporter_id = auth.uid());

DROP POLICY IF EXISTS "chat_reports_select_admin" ON public.chat_reports;
CREATE POLICY "chat_reports_select_admin"
  ON public.chat_reports FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "chat_reports_update_admin" ON public.chat_reports;
CREATE POLICY "chat_reports_update_admin"
  ON public.chat_reports FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

CREATE INDEX IF NOT EXISTS idx_support_requests_user_id
  ON public.support_requests(user_id);
CREATE INDEX IF NOT EXISTS idx_support_requests_status
  ON public.support_requests(status);
CREATE INDEX IF NOT EXISTS idx_support_requests_created_at
  ON public.support_requests(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_chat_reports_reporter_id
  ON public.chat_reports(reporter_id);
CREATE INDEX IF NOT EXISTS idx_chat_reports_status
  ON public.chat_reports(status);
