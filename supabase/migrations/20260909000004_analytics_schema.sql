-- Migration: schema for the admin operating dashboard. Additive only.
--
-- No table is altered, no column changed, no policy weakened. Everything here
-- is new and independently droppable.
--
-- platform_config is NOT created. app_config already exists (149 rows,
-- key/value/value_type/description), is already admin-editable through
-- admin_pricing_screen, and already hot-reloads via a Realtime channel. A
-- second config table would be a second source of truth for the same thing.

-- ── Config the dashboard reads ─────────────────────────────────────────────
-- Deliberately seeded at 0 rather than with figures from the business plan:
-- ops cost and break-even targets are the operator's numbers, and a plausible
-- placeholder is indistinguishable on screen from a real one. The RPCs guard
-- against division by zero and the UI says when a value is unset.
INSERT INTO public.app_config (key, value, value_type, description) VALUES
  ('monthly_ops_cost', '0', 'number',
   'Total monthly operating cost. Drives break-even. Set this before trusting the dashboard.'),
  ('food_breakeven_target_daily', '0', 'number',
   'Target food orders per day to break even. 0 = derive from monthly_ops_cost.'),
  ('food_breakeven_target_monthly', '0', 'number',
   'Target food orders per month to break even. 0 = derive from monthly_ops_cost.'),
  ('grocery_sla_minutes', '45', 'number',
   'Grocery delivery SLA in minutes, order placed to delivered.'),
  ('sla_warning_thresholds', '30,35,40,45', 'string',
   'Comma-separated minute boundaries for the SLA buckets.')
ON CONFLICT (key) DO UPDATE
  SET value_type = EXCLUDED.value_type,
      description = EXCLUDED.description;

-- ── Status history ─────────────────────────────────────────────────────────
-- The orders table already has per-stage timestamp columns
-- (confirmed_at, preparing_started_at, ready_at, picked_up_at, on_the_way_at,
-- delivered_at) — and every one of them is empty. 0 of 14 orders. Nothing
-- writes them. So the SLA question is not "where do we store stage times", it
-- is "nobody records them at all".
--
-- This table records them from now on. It will be near-empty until orders flow
-- through it, and the dashboard says so rather than implying otherwise.

CREATE TABLE public.order_status_events (
  id          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  order_id    UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  status      TEXT NOT NULL,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- INFERRED from the status, not observed. A trigger sees the new status, not
  -- who caused it. 'preparing' is the restaurant's move and 'picked_up' the
  -- rider's, so the mapping is sound, but it is an inference and the dashboard
  -- labels it as attribution rather than fact.
  actor_type  TEXT NOT NULL CHECK (actor_type IN
              ('customer','store','rider','dispatch','system')),
  metadata    JSONB NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX idx_ose_order_occurred  ON public.order_status_events (order_id, occurred_at);
CREATE INDEX idx_ose_status_occurred ON public.order_status_events (status, occurred_at);
CREATE INDEX idx_ose_occurred        ON public.order_status_events (occurred_at);

ALTER TABLE public.order_status_events ENABLE ROW LEVEL SECURITY;
-- No customer-facing policy: this feeds admin analytics only, and the RPCs are
-- SECURITY DEFINER. Base-table access stays closed.

-- ── Which actor a status belongs to ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.order_status_actor(p_status TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_status
    WHEN 'pending'    THEN 'customer'
    WHEN 'confirmed'  THEN 'store'
    WHEN 'preparing'  THEN 'store'
    WHEN 'ready'      THEN 'store'
    WHEN 'picked_up'  THEN 'rider'
    WHEN 'on_the_way' THEN 'rider'
    WHEN 'delivered'  THEN 'rider'
    WHEN 'cancelled'  THEN 'system'
    ELSE 'system'
  END;
$$;

-- ── Record transitions. Does NOT change transition logic. ──────────────────
-- Writes to a different table than it reads, so it cannot recurse — the
-- failure mode this codebase has already had with a push trigger.
CREATE OR REPLACE FUNCTION public.record_order_status_event()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NULL;
  END IF;
  INSERT INTO public.order_status_events (order_id, status, occurred_at, actor_type)
  VALUES (NEW.id, NEW.status, now(), public.order_status_actor(NEW.status));
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_record_order_status_insert ON public.orders;
CREATE TRIGGER trg_record_order_status_insert
AFTER INSERT ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.record_order_status_event();

DROP TRIGGER IF EXISTS trg_record_order_status_update ON public.orders;
CREATE TRIGGER trg_record_order_status_update
AFTER UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.record_order_status_event();

-- ── Backfill what history actually exists ──────────────────────────────────
-- Only ordered_at and delivered_at are populated, so only those are recovered.
-- Inventing the rest would be fabricating operational history.
INSERT INTO public.order_status_events (order_id, status, occurred_at, actor_type)
SELECT o.id, 'pending', o.ordered_at, 'customer'
FROM public.orders o WHERE o.ordered_at IS NOT NULL;

INSERT INTO public.order_status_events (order_id, status, occurred_at, actor_type)
SELECT o.id, 'delivered', o.delivered_at, 'rider'
FROM public.orders o WHERE o.delivered_at IS NOT NULL;

NOTIFY pgrst, 'reload schema';
