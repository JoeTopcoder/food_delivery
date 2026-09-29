-- HotBite Driver Priority System.
-- Trusted, backend-computed driver standing that influences (not dictates)
-- order assignment. Reuses drivers.driver_score/tier/rating/acceptance_rate/
-- on_time_rate and order timestamps. All config is admin-editable (no app
-- release needed). Drivers can never write their own score.

-- ── 1. Config (single row, JSONB, admin-editable) ─────────────────────────
CREATE TABLE IF NOT EXISTS public.driver_priority_config (
  id          integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  weights     jsonb NOT NULL,      -- factor -> weight (sums ~1.0)
  thresholds  jsonb NOT NULL,      -- standing -> [min,max]
  min_deliveries jsonb NOT NULL,   -- provisional/developing/eligible cutoffs
  rolling     jsonb NOT NULL,      -- window: days / max deliveries
  assignment  jsonb NOT NULL,      -- assignment-score weights + class min standing
  updated_at  timestamptz NOT NULL DEFAULT now(),
  updated_by  uuid
);

INSERT INTO public.driver_priority_config (id, weights, thresholds, min_deliveries, rolling, assignment)
VALUES (
  1,
  '{"customer_rating":0.25,"on_time":0.25,"completion":0.20,"acceptance":0.10,"pickup":0.10,"complaints":0.10}'::jsonb,
  '{"ELITE":[90,100],"PRIORITY":[80,89],"GOOD_STANDING":[70,79],"STANDARD":[50,69],"NEEDS_IMPROVEMENT":[0,49]}'::jsonb,
  '{"provisional":10,"developing":50}'::jsonb,
  '{"days":30,"max_deliveries":100}'::jsonb,
  '{"distance":0.40,"priority":0.35,"workload":0.15,"other":0.10,"class_min_standing":{"PRIORITY":"GOOD_STANDING","PREMIUM":"PRIORITY"}}'::jsonb
)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.driver_priority_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS dpc_read ON public.driver_priority_config;
CREATE POLICY dpc_read ON public.driver_priority_config FOR SELECT USING (true);
DROP POLICY IF EXISTS dpc_admin ON public.driver_priority_config;
CREATE POLICY dpc_admin ON public.driver_priority_config
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── 2. Driver standing columns (reuse driver_score) ───────────────────────
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS priority_standing text,
  ADD COLUMN IF NOT EXISTS priority_provisional boolean NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS priority_stats jsonb,
  ADD COLUMN IF NOT EXISTS priority_updated_at timestamptz;

-- ── 3. Audit log — every score change is traceable, never driver-editable ─
CREATE TABLE IF NOT EXISTS public.driver_priority_events (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  driver_id     uuid NOT NULL,
  order_id      uuid,
  event_type    text NOT NULL,         -- recompute | penalty | admin_adjust | review_reversal
  score_change  numeric,
  previous_score numeric,
  new_score     numeric,
  reason        text,
  review_status text NOT NULL DEFAULT 'none', -- none | requested | confirmed | reversed
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid
);
CREATE INDEX IF NOT EXISTS idx_dpe_driver ON public.driver_priority_events(driver_id, created_at DESC);

ALTER TABLE public.driver_priority_events ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS dpe_driver_read ON public.driver_priority_events;
CREATE POLICY dpe_driver_read ON public.driver_priority_events FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.drivers d WHERE d.id = driver_id AND d.user_id = auth.uid())
         OR public.is_admin());
DROP POLICY IF EXISTS dpe_admin_write ON public.driver_priority_events;
CREATE POLICY dpe_admin_write ON public.driver_priority_events FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── 4. Order classification ───────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS priority_class text NOT NULL DEFAULT 'NORMAL'
    CHECK (priority_class IN ('NORMAL','PRIORITY','PREMIUM'));

-- ── 5. Protect score columns from client tampering ────────────────────────
-- A logged-in driver's UPDATE (auth.uid() = their user_id) must not change any
-- performance/standing field. Only SECURITY DEFINER RPCs (auth.uid() NULL in
-- that context is not the case; we detect by a session flag) or admins may.
CREATE OR REPLACE FUNCTION public.protect_driver_score_fields()
RETURNS trigger LANGUAGE plpgsql AS $fn$
BEGIN
  -- Allow when the trusted compute path set this GUC, or the caller is admin.
  IF current_setting('hotbite.priority_write', true) = 'on'
     OR public.is_admin() THEN
    RETURN NEW;
  END IF;
  -- Otherwise pin protected fields to their old values.
  NEW.driver_score        := OLD.driver_score;
  NEW.tier                := OLD.tier;
  NEW.priority_standing   := OLD.priority_standing;
  NEW.priority_provisional:= OLD.priority_provisional;
  NEW.priority_stats      := OLD.priority_stats;
  NEW.rating              := OLD.rating;
  NEW.acceptance_rate     := OLD.acceptance_rate;
  NEW.on_time_rate        := OLD.on_time_rate;
  NEW.completed_deliveries:= OLD.completed_deliveries;
  NEW.cancelled_deliveries:= OLD.cancelled_deliveries;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_protect_driver_score ON public.drivers;
CREATE TRIGGER trg_protect_driver_score
  BEFORE UPDATE ON public.drivers
  FOR EACH ROW EXECUTE FUNCTION public.protect_driver_score_fields();

NOTIFY pgrst, 'reload schema';
