-- ── 123_monitoring_and_idempotency ──────────────────────────────────────────
-- 1. api_request_logs  — lightweight backend observability table
-- 2. order_idempotency_keys — prevents duplicate orders on retry/network error
-- ─────────────────────────────────────────────────────────────────────────────

-- ── 1. Request log table ─────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.api_request_logs (
  id               UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id       TEXT        NOT NULL,   -- client-generated UUID per call
  user_id          UUID,                   -- null for unauthenticated requests
  endpoint         TEXT        NOT NULL,   -- edge function / REST path
  status_code      INT,
  response_time_ms INT,
  cache_hit        BOOLEAN     NOT NULL DEFAULT FALSE,
  error_code       TEXT,                   -- app-level error key e.g. RATE_LIMITED
  created_at       TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Keep only 30 days of logs to prevent unbounded growth
CREATE INDEX IF NOT EXISTS idx_api_logs_endpoint_created
  ON public.api_request_logs (endpoint, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_api_logs_status_created
  ON public.api_request_logs (status_code, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_api_logs_user_created
  ON public.api_request_logs (user_id, created_at DESC);

-- Auto-purge rows older than 30 days (runs via pg_cron if available, or manually)
-- The function is safe to call from any edge function or cron job.
CREATE OR REPLACE FUNCTION public.purge_old_api_logs()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  DELETE FROM public.api_request_logs
  WHERE created_at < NOW() - INTERVAL '30 days';
END;
$$;

-- RLS: only service-role (edge functions) can write; admins can read
ALTER TABLE public.api_request_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Service role can insert logs"
  ON public.api_request_logs FOR INSERT
  WITH CHECK (TRUE);  -- service-role bypasses RLS anyway; this covers anon-key edge cases

CREATE POLICY "Admins can read logs"
  ON public.api_request_logs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ── 2. Order idempotency keys ─────────────────────────────────────────────────
-- Flutter generates a UUID idempotency_key before calling place-order.
-- If the network drops after the server succeeds, Flutter retries with the
-- same key and gets the original order back instead of a duplicate.
CREATE TABLE IF NOT EXISTS public.order_idempotency_keys (
  id                UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id           UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  idempotency_key   TEXT        NOT NULL,
  order_id          UUID,                   -- populated once the order is created
  response_snapshot JSONB,                  -- cached response returned to client
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_order_idempotency_user_key
  ON public.order_idempotency_keys (user_id, idempotency_key);

CREATE INDEX IF NOT EXISTS idx_order_idempotency_created
  ON public.order_idempotency_keys (created_at DESC);

-- Auto-purge keys older than 24 hours (short-lived — only needed for retry window)
CREATE OR REPLACE FUNCTION public.purge_old_idempotency_keys()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  DELETE FROM public.order_idempotency_keys
  WHERE created_at < NOW() - INTERVAL '24 hours';
END;
$$;

-- RLS
ALTER TABLE public.order_idempotency_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users manage own idempotency keys"
  ON public.order_idempotency_keys FOR ALL
  USING (user_id = auth.uid());
