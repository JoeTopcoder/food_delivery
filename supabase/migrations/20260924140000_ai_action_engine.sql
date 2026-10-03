-- ============================================================================
-- HotBite AI Staff — Stage 8: approved-action engine
-- ============================================================================
-- Turns an APPROVED suggestion into real, verified work through a FIXED
-- server-side capability registry. Hard rules enforced in the database, not the
-- prompt/UI:
--   * A permanent PRICING/FEE boundary: no engine path can create, edit or
--     delete any product price, sale price, HotBite+ member price, delivery /
--     service / priority / any customer or partner fee. Enforced three ways:
--       (1) no capability in the registry writes a price/fee column;
--       (2) the engine runs in ONE transaction that arms a guard GUC
--           (app.ai_exec='1'); a trigger on menus/restaurants/app_config raises
--           if any price/fee column is touched while that guard is armed;
--       (3) pricing-typed proposals are marked requires_manual_admin and the
--           engine refuses to execute them — it only prepares a human task.
--   * No generic write/SQL/HTTP tool: the engine dispatches a closed set of
--     typed capabilities; there is no arbitrary-SQL or arbitrary-HTTP path.
--   * Idempotent: an (idempotency_key) uniquely guards each execution.
--   * Vague approvals cannot execute: a proposal must carry an allow-listed
--     action_type + payload or the engine rejects it.
-- ============================================================================

-- ── fixed capability registry ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_action_types (
  action_type             text PRIMARY KEY,
  label                   text NOT NULL,
  category                text NOT NULL,
  requires_manual_admin   boolean NOT NULL DEFAULT false, -- pricing/fees etc.
  has_external_effect     boolean NOT NULL DEFAULT false,
  needs_second_confirm    boolean NOT NULL DEFAULT false,
  description             text
);

INSERT INTO public.ai_action_types
  (action_type, label, category, requires_manual_admin, has_external_effect, needs_second_confirm, description) VALUES
 ('create_admin_task','Create & assign an admin task','ops',false,false,false,'Create a tracked work item for the responsible admin/team.'),
 ('investigate_orders','Investigate affected orders','ops',false,false,false,'Attach a verified, read-only case list of affected orders to a task.'),
 ('flag_catalogue_issue','Flag a catalogue problem (no price change)','catalogue',false,false,false,'Route a non-price catalogue problem for human correction.'),
 ('assign_support_cases','Assign unresolved support cases','support',false,false,false,'Assign existing open support requests to a reviewer (existing triage workflow).'),
 ('prepare_rider_coverage_plan','Prepare a rider coverage plan','dispatch',false,false,false,'Compute coverage gaps and assign a plan to the dispatch team.'),
 ('create_admin_alert','Create an internal admin alert','ops',false,false,false,'Raise an internal alert/reminder for admins.'),
 ('open_store_performance_case','Open a store performance case','stores',false,false,false,'Open and track a store performance case.'),
 ('draft_partner_message','Draft a partner/customer message','comms',false,false,false,'Prepare a DRAFT message for an admin to review. Never sends it.'),
 ('prepare_pricing_change','Prepare a pricing/fee change (manual only)','pricing',true,false,false,'Investigate and prepare an exact proposed price/fee change as a MANUAL admin task. AI never applies it.'),
 ('send_partner_message','Send a partner/customer message','comms',false,true,true,'External send — routed to a human with a separate exact confirmation. Engine never auto-sends.')
ON CONFLICT (action_type) DO NOTHING;

ALTER TABLE public.ai_action_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ai_action_types_read ON public.ai_action_types;
CREATE POLICY ai_action_types_read ON public.ai_action_types FOR SELECT TO authenticated USING (public.is_admin());
GRANT SELECT ON public.ai_action_types TO authenticated;

-- ── real work items for humans/teams ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_admin_tasks (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  suggestion_id    uuid REFERENCES public.ai_suggestions(id) ON DELETE SET NULL,
  title            text NOT NULL,
  description      text,
  category         text NOT NULL DEFAULT 'ops',
  priority         text NOT NULL DEFAULT 'medium',
  assignee_team    text,
  assigned_to      uuid REFERENCES public.users(id) ON DELETE SET NULL,
  status           text NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open','in_progress','done','cancelled')),
  related_records  jsonb NOT NULL DEFAULT '[]'::jsonb,
  evidence         jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_by       uuid REFERENCES public.users(id) ON DELETE SET NULL,
  completed_by     uuid REFERENCES public.users(id) ON DELETE SET NULL,
  due_at           timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  completed_at     timestamptz
);
CREATE INDEX IF NOT EXISTS idx_ai_admin_tasks_status ON public.ai_admin_tasks(status);
CREATE INDEX IF NOT EXISTS idx_ai_admin_tasks_suggestion ON public.ai_admin_tasks(suggestion_id);
ALTER TABLE public.ai_admin_tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ai_admin_tasks_read ON public.ai_admin_tasks;
DROP POLICY IF EXISTS ai_admin_tasks_update ON public.ai_admin_tasks;
CREATE POLICY ai_admin_tasks_read ON public.ai_admin_tasks FOR SELECT TO authenticated USING (public.is_admin());
CREATE POLICY ai_admin_tasks_update ON public.ai_admin_tasks FOR UPDATE TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin());
GRANT SELECT, UPDATE ON public.ai_admin_tasks TO authenticated;

-- ── execution audit trail ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_action_executions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  suggestion_id    uuid REFERENCES public.ai_suggestions(id) ON DELETE SET NULL,
  action_type      text NOT NULL,
  approved_payload jsonb NOT NULL DEFAULT '{}'::jsonb,
  idempotency_key  text NOT NULL UNIQUE,
  status           text NOT NULL DEFAULT 'queued'
                     CHECK (status IN ('queued','executing','verifying','completed','failed','blocked','waiting_human')),
  attempted        jsonb NOT NULL DEFAULT '{}'::jsonb,
  result           jsonb NOT NULL DEFAULT '{}'::jsonb,
  before_values    jsonb,
  after_values     jsonb,
  records_affected jsonb NOT NULL DEFAULT '[]'::jsonb,
  verification     jsonb,
  external_effect  boolean NOT NULL DEFAULT false,
  task_id          uuid REFERENCES public.ai_admin_tasks(id) ON DELETE SET NULL,
  executor         uuid,
  error            text,
  created_at       timestamptz NOT NULL DEFAULT now(),
  completed_at     timestamptz
);
CREATE INDEX IF NOT EXISTS idx_ai_action_exec_suggestion ON public.ai_action_executions(suggestion_id);
CREATE INDEX IF NOT EXISTS idx_ai_action_exec_status ON public.ai_action_executions(status);
ALTER TABLE public.ai_action_executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ai_action_exec_read ON public.ai_action_executions;
CREATE POLICY ai_action_exec_read ON public.ai_action_executions FOR SELECT TO authenticated USING (public.is_admin());
GRANT SELECT ON public.ai_action_executions TO authenticated;

-- ── extend suggestions with the action proposal + execution lifecycle ──────
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS action_type text REFERENCES public.ai_action_types(action_type);
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS action_payload jsonb;
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS approved_payload jsonb;
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS requires_manual_admin boolean NOT NULL DEFAULT false;
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS has_external_effect boolean NOT NULL DEFAULT false;
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS approved_by uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS approved_at timestamptz;
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS action_status text NOT NULL DEFAULT 'suggested'
  CHECK (action_status IN ('suggested','awaiting_approval','awaiting_more_detail','approved','queued','executing','verifying','completed','assigned_to_human','blocked','failed','cancelled'));

-- ============================================================================
-- PRICING/FEE GUARD — DB trigger. Raises if a price/fee column is written while
-- the AI execution guard (app.ai_exec) is armed. This is a hard backstop: even
-- a future buggy capability cannot slip a price change through the engine.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.ai_guard_no_price_writes()
RETURNS trigger LANGUAGE plpgsql AS $g$
BEGIN
  IF current_setting('app.ai_exec', true) <> '1' THEN
    RETURN NEW; -- normal human/admin path is unaffected
  END IF;
  IF TG_TABLE_NAME = 'menus' THEN
    IF TG_OP = 'INSERT' OR NEW.price IS DISTINCT FROM OLD.price
       OR NEW.discount IS DISTINCT FROM OLD.discount
       OR NEW.hotbite_plus_price IS DISTINCT FROM OLD.hotbite_plus_price THEN
      RAISE EXCEPTION 'AI executor may not change product/member prices (menus)';
    END IF;
  ELSIF TG_TABLE_NAME = 'restaurants' THEN
    IF TG_OP='INSERT' OR NEW.delivery_fee IS DISTINCT FROM OLD.delivery_fee
       OR NEW.service_fee IS DISTINCT FROM OLD.service_fee
       OR NEW.commission_rate IS DISTINCT FROM OLD.commission_rate
       OR NEW.price_tier IS DISTINCT FROM OLD.price_tier THEN
      RAISE EXCEPTION 'AI executor may not change partner fees (restaurants)';
    END IF;
  ELSIF TG_TABLE_NAME = 'app_config' THEN
    IF NEW.key ILIKE '%fee%' OR NEW.key ILIKE '%price%' OR NEW.key ILIKE '%surge%'
       OR NEW.key ILIKE '%commission%' THEN
      RAISE EXCEPTION 'AI executor may not change fee/price config (app_config: %)', NEW.key;
    END IF;
  END IF;
  RETURN NEW;
END;
$g$;

DROP TRIGGER IF EXISTS trg_ai_guard_menus ON public.menus;
CREATE TRIGGER trg_ai_guard_menus BEFORE INSERT OR UPDATE ON public.menus
  FOR EACH ROW EXECUTE FUNCTION public.ai_guard_no_price_writes();
DROP TRIGGER IF EXISTS trg_ai_guard_restaurants ON public.restaurants;
CREATE TRIGGER trg_ai_guard_restaurants BEFORE INSERT OR UPDATE ON public.restaurants
  FOR EACH ROW EXECUTE FUNCTION public.ai_guard_no_price_writes();
DROP TRIGGER IF EXISTS trg_ai_guard_app_config ON public.app_config;
CREATE TRIGGER trg_ai_guard_app_config BEFORE INSERT OR UPDATE ON public.app_config
  FOR EACH ROW EXECUTE FUNCTION public.ai_guard_no_price_writes();

NOTIFY pgrst, 'reload schema';
