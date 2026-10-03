-- ============================================================================
-- CALL FALLBACK (private telephone bridge) — backend foundation.
--
-- Adds a telephone fallback ALONGSIDE the existing Agora calling system. Agora
-- is unchanged; this only adds a separate, feature-flagged path that bridges a
-- driver and customer over their real phone numbers via a backend-managed
-- provider (Twilio), WITHOUT ever exposing the customer's number to the driver.
--
-- Security model:
--  • Phone numbers are NEVER stored in the driver-readable session row and are
--    NEVER returned to the driver. They are resolved server-side (service_role)
--    at dial time from users.phone / drivers.phone_number.
--  • Provider call SIDs + sanitized failure codes live on the row but are only
--    reachable by service_role / admin; drivers read a safe projection via RPC.
--  • Every driver action is authorized (assigned to the order, order eligible,
--    feature enabled, within attempt/cooldown/grace limits) and re-checked
--    immediately before the customer leg is dialed.
-- ============================================================================

-- ── Feature flag + tunables (admin-configurable via app_config) ─────────────
INSERT INTO public.app_config (key, value) VALUES
  ('call_fallback_enabled',           'false'),   -- master switch (default OFF)
  ('call_fallback_connect_timeout_s', '15'),      -- accepted call never connects
  ('call_fallback_reconnect_grace_s', '10'),      -- established call drops
  ('call_fallback_no_answer_s',       '30'),      -- invite unanswered -> manual button
  ('call_fallback_max_attempts',      '2'),       -- per order per driver
  ('call_fallback_cooldown_s',        '60'),      -- between attempts
  ('call_fallback_max_duration_s',    '300'),     -- max connected bridge duration
  ('call_fallback_grace_minutes',     '15'),      -- post-delivery calling window
  ('call_fallback_service_countries', 'JM,US,CA'),-- allowed destination countries
  ('call_fallback_provider',          'mock')     -- 'mock' until Twilio provisioned
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.call_fallback_enabled()
  RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT value IN ('true','1') FROM public.app_config
                   WHERE key='call_fallback_enabled'), false);
$$;
GRANT EXECUTE ON FUNCTION public.call_fallback_enabled() TO authenticated, anon, service_role;

CREATE OR REPLACE FUNCTION public.cf_config_int(p_key text, p_default int)
  RETURNS int LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT coalesce((SELECT NULLIF(regexp_replace(value,'\D','','g'),'')::int
                   FROM public.app_config WHERE key=p_key), p_default);
$$;

-- ── Session table (NO phone numbers; SIDs admin/service-only) ────────────────
CREATE TABLE IF NOT EXISTS public.call_fallback_sessions (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id            uuid REFERENCES public.calls(id) ON DELETE SET NULL,
  order_id           uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  driver_user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  customer_user_id   uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  reason             text NOT NULL,                 -- connect_timeout|reconnect_failed|no_answer_manual
  status             text NOT NULL DEFAULT 'requested',
  -- requested -> dialing_driver -> awaiting_driver_press -> dialing_customer
  --           -> bridged -> completed | failed | cancelled | no_answer
  provider           text NOT NULL DEFAULT 'mock',
  attempt_no         int  NOT NULL DEFAULT 1,
  provider_driver_sid   text,                        -- admin/service only
  provider_customer_sid text,                        -- admin/service only
  failure_code       text,                           -- sanitized
  cost_amount        numeric,
  deadline_at        timestamptz,                    -- durable timeout (survives restarts)
  dialed_customer_at timestamptz,
  bridged_at         timestamptz,
  ended_at           timestamptz,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- One active fallback per original call attempt (dedupe duplicate requests).
CREATE UNIQUE INDEX IF NOT EXISTS uq_cf_active_per_call
  ON public.call_fallback_sessions (call_id)
  WHERE status IN ('requested','dialing_driver','awaiting_driver_press','dialing_customer','bridged');

CREATE INDEX IF NOT EXISTS idx_cf_order   ON public.call_fallback_sessions(order_id);
CREATE INDEX IF NOT EXISTS idx_cf_driver  ON public.call_fallback_sessions(driver_user_id);
CREATE INDEX IF NOT EXISTS idx_cf_status  ON public.call_fallback_sessions(status);
CREATE INDEX IF NOT EXISTS idx_cf_deadline ON public.call_fallback_sessions(deadline_at)
  WHERE status IN ('requested','dialing_driver','awaiting_driver_press','dialing_customer','bridged');

ALTER TABLE public.call_fallback_sessions ENABLE ROW LEVEL SECURITY;

-- Base table: NO direct driver access (phones/SIDs live here). Service role runs
-- the engine; admins can read for the call log. Drivers use the safe RPCs below.
DROP POLICY IF EXISTS cf_admin_read ON public.call_fallback_sessions;
CREATE POLICY cf_admin_read ON public.call_fallback_sessions
  FOR SELECT TO authenticated USING (public.is_admin());

REVOKE ALL ON public.call_fallback_sessions FROM anon, authenticated;
GRANT SELECT ON public.call_fallback_sessions TO authenticated;  -- gated by is_admin() policy

NOTIFY pgrst, 'reload schema';
