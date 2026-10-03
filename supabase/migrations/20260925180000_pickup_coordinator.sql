-- ============================================================================
-- AI Staff — Restaurant Pickup Coordinator: 15-minute preparation follow-up.
-- ----------------------------------------------------------------------------
-- Builds on the existing remind_stores_mark_ready nudge. When a restaurant has
-- had an order on its dashboard for 15 minutes without moving it to Preparing
-- or Ready, the Pickup Coordinator places ONE follow-up call, records the
-- outcome, and (only with explicit restaurant authorization) schedules a
-- server-side automatic Ready transition.
--
-- INTEGRATION BOUNDARY: HotBite has no outbound PSTN telephony (the `calls`
-- table is Agora in-app voice). This migration builds the entire workflow —
-- trigger, idempotent call queue, condition rechecks, scheduling, authorized
-- status transitions, timeline + rider notification. The ACTUAL voice dialing
-- and speech capture must be supplied by a telephony/IVR provider that posts
-- answers back via pickup_record_call_outcome(). Nothing here fabricates a
-- conversation or marks Ready without the restaurant's recorded authorization.
--
-- In HotBite's flow an order sits at pending/confirmed on the restaurant
-- dashboard until the restaurant's "Accept" moves it to preparing. So
-- "accepted into the queue but no prep update" = status still pending/confirmed
-- 15 minutes after it arrived. Acceptance time = COALESCE(confirmed_at, created_at).
-- ============================================================================

-- 0. Order column for a stored expected-ready time (no auto-Ready authorization).
ALTER TABLE orders ADD COLUMN IF NOT EXISTS expected_ready_at timestamptz;

-- 1. AI staff role. -----------------------------------------------------------
INSERT INTO ai_staff_roles (slug, title, department, job_description,
  data_categories, daily_reporting_requirements, max_suggestions, model, status, sort_order)
VALUES (
  'restaurant_pickup_coordinator', 'Restaurant Pickup Coordinator', 'Operations',
  'Places a single 15-minute preparation follow-up call to a restaurant that has '
  || 'not moved an accepted order to Preparing or Ready. Confirms whether prep is '
  || 'underway, the expected ready time, and whether HotBite may auto-mark Ready at '
  || 'that time. Updates status only through the authorized workflow and never marks '
  || 'Ready without the restaurant''s explicit recorded authorization.',
  ARRAY['orders','restaurant_pickup_calls','restaurant_ready_jobs'],
  'Calls attempted, prep-underway confirmations, ready times captured, auto-Ready '
  || 'authorizations, scheduled/executed automatic Ready transitions, delays and '
  || 'unfulfillable orders escalated.',
  3, 'gpt-4o-mini', 'active', 50)
ON CONFLICT (slug) DO UPDATE SET
  title = EXCLUDED.title, department = EXCLUDED.department,
  job_description = EXCLUDED.job_description,
  data_categories = EXCLUDED.data_categories,
  daily_reporting_requirements = EXCLUDED.daily_reporting_requirements,
  status = 'active', updated_at = now();

-- 2. Call queue (one 15-minute follow-up per order = idempotency). ------------
CREATE TABLE IF NOT EXISTS public.restaurant_pickup_calls (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id              uuid NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
  restaurant_id         uuid REFERENCES restaurants(id),
  status                text NOT NULL DEFAULT 'queued',  -- queued|cancelled|dialing|completed|failed
  queued_at             timestamptz NOT NULL DEFAULT now(),
  dialed_at             timestamptz,
  completed_at          timestamptz,
  -- recorded conversation outcomes (supplied by the telephony/IVR integration):
  prep_underway         boolean,
  confirmed_ready_at    timestamptz,
  auto_ready_authorized boolean,
  delay_reported        boolean,
  outcome               text,    -- ready_now|preparing|scheduled_auto|expected_only|delay|unfulfillable|no_answer|conditions_changed
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT rpc_status_valid CHECK (status IN ('queued','cancelled','dialing','completed','failed'))
);
CREATE INDEX IF NOT EXISTS idx_rpc_status ON public.restaurant_pickup_calls(status);
ALTER TABLE public.restaurant_pickup_calls ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rpc_admin_read ON public.restaurant_pickup_calls;
CREATE POLICY rpc_admin_read ON public.restaurant_pickup_calls FOR SELECT
  USING (EXISTS (SELECT 1 FROM users u WHERE u.id=auth.uid() AND u.role='admin'));

-- 3. Scheduled automatic-Ready jobs (only when authorized). -------------------
CREATE TABLE IF NOT EXISTS public.restaurant_ready_jobs (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     uuid NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  call_id      uuid REFERENCES restaurant_pickup_calls(id) ON DELETE SET NULL,
  run_at       timestamptz NOT NULL,
  status       text NOT NULL DEFAULT 'scheduled',  -- scheduled|done|cancelled|superseded
  authorized   boolean NOT NULL DEFAULT true,
  source       text,
  created_at   timestamptz NOT NULL DEFAULT now(),
  executed_at  timestamptz,
  CONSTRAINT rrj_status_valid CHECK (status IN ('scheduled','done','cancelled','superseded'))
);
-- At most one ACTIVE scheduled job per order (replacements supersede).
CREATE UNIQUE INDEX IF NOT EXISTS uq_rrj_active ON public.restaurant_ready_jobs(order_id)
  WHERE status = 'scheduled';
ALTER TABLE public.restaurant_ready_jobs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rrj_admin_read ON public.restaurant_ready_jobs;
CREATE POLICY rrj_admin_read ON public.restaurant_ready_jobs FOR SELECT
  USING (EXISTS (SELECT 1 FROM users u WHERE u.id=auth.uid() AND u.role='admin'));

-- 4. Config: the follow-up threshold (minutes).
INSERT INTO app_config(key, value)
SELECT 'pickup_followup_minutes', '15'
WHERE NOT EXISTS (SELECT 1 FROM app_config WHERE key='pickup_followup_minutes');

NOTIFY pgrst, 'reload schema';
