-- Stage 6: extend the suggestion workflow with the assign / in-progress /
-- complete states and per-transition audit columns (who + when), plus a
-- resolver on alerts. Additive and idempotent; no existing data affected.

-- Widen the status vocabulary: New(pending) → approved/rejected → assigned →
-- in_progress → completed (dismissed stays as a terminal decline).
ALTER TABLE public.ai_suggestions DROP CONSTRAINT IF EXISTS ai_suggestions_status_check;
ALTER TABLE public.ai_suggestions
  ADD CONSTRAINT ai_suggestions_status_check
  CHECK (status IN ('pending','approved','rejected','assigned','in_progress','completed','dismissed','implemented'));

-- Per-transition audit (reviewed_by/reviewed_at already exist for approve/reject).
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS assigned_to   uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS assigned_by   uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS assigned_at   timestamptz;
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS completed_by  uuid REFERENCES public.users(id) ON DELETE SET NULL;
ALTER TABLE public.ai_suggestions ADD COLUMN IF NOT EXISTS completed_at  timestamptz;

-- Alerts: record who resolved (acknowledged_by/at already exist).
ALTER TABLE public.ai_urgent_alerts ADD COLUMN IF NOT EXISTS resolved_by uuid REFERENCES public.users(id) ON DELETE SET NULL;

NOTIFY pgrst, 'reload schema';
