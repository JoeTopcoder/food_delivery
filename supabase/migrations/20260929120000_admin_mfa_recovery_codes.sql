-- ============================================================================
-- Admin 2FA email recovery codes.
-- When an admin can't reach their authenticator app, they can have a one-time
-- code emailed to their account email and use it to pass the step-up challenge.
-- Codes are stored HASHED (sha256 with a server-side pepper, done in the
-- admin-recovery-code edge function), short-lived, and single-use.
--
-- The table is service-role only (RLS on, no policies) — all reads/writes go
-- through the edge function running with the service role. Nothing here is
-- reachable by anon/authenticated clients directly.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.admin_mfa_recovery_codes (
  id         bigserial PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code_hash  text NOT NULL,
  expires_at timestamptz NOT NULL,
  used_at    timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS admin_mfa_recovery_codes_user_idx
  ON public.admin_mfa_recovery_codes (user_id, used_at, expires_at);

ALTER TABLE public.admin_mfa_recovery_codes ENABLE ROW LEVEL SECURITY;
-- No policies on purpose: only the service role (edge function) touches this.

NOTIFY pgrst, 'reload schema';
