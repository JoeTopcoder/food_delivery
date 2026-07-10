-- ─────────────────────────────────────────────────────────────────────────────
-- AI Support Agent — v1 of the 7Dash AI Operations layer.
-- Scope: one agent (customer support draft/reply), with a generic, reusable
-- audit table (ai_agent_runs) so future agents share the same audit trail
-- instead of each inventing their own logging.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.ai_agent_runs (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  agent_name   text NOT NULL,
  entity_type  text NOT NULL,
  entity_id    uuid NOT NULL,
  input        jsonb NOT NULL DEFAULT '{}'::jsonb,
  output       jsonb,
  model        text,
  status       text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending', 'completed', 'failed')),
  error        text,
  created_by   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ai_agent_runs ENABLE ROW LEVEL SECURITY;

-- Admin-only visibility. All writes happen via service-role edge functions,
-- which bypass RLS entirely, so no INSERT/UPDATE policy is needed here.
DROP POLICY IF EXISTS "ai_agent_runs_select_admin" ON public.ai_agent_runs;
CREATE POLICY "ai_agent_runs_select_admin"
  ON public.ai_agent_runs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

CREATE INDEX IF NOT EXISTS idx_ai_agent_runs_entity
  ON public.ai_agent_runs(entity_type, entity_id);
CREATE INDEX IF NOT EXISTS idx_ai_agent_runs_agent_created
  ON public.ai_agent_runs(agent_name, created_at DESC);

-- ── Support Agent fields on support_requests ────────────────────────────────

ALTER TABLE public.support_requests
  ADD COLUMN IF NOT EXISTS ai_draft_reply      text,
  ADD COLUMN IF NOT EXISTS ai_suggested_action text
    CHECK (ai_suggested_action IN ('none', 'reply_only', 'credit', 'refund_manual', 'escalate')),
  ADD COLUMN IF NOT EXISTS ai_suggested_amount numeric,
  ADD COLUMN IF NOT EXISTS ai_confidence       numeric,
  ADD COLUMN IF NOT EXISTS ai_reasoning        text,
  ADD COLUMN IF NOT EXISTS ai_run_id           uuid REFERENCES public.ai_agent_runs(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS ai_status           text
    CHECK (ai_status IN ('drafted', 'approved', 'rejected', 'sent')),
  ADD COLUMN IF NOT EXISTS ai_final_reply      text,
  ADD COLUMN IF NOT EXISTS reviewed_by         uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS reviewed_at         timestamptz;
