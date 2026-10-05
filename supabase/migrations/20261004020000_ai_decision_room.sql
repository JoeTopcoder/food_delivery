-- ============================================================================
-- AI DECISION ROOM — admin-only multi-model advisory workflow.
--
-- OpenAI and Claude each assess a question, review each other, then a synthesis
-- model produces a final structured recommendation (agreements, disagreements,
-- assumptions, facts to verify, exactly three next actions). Advisory ONLY —
-- nothing here changes prices, orders, payments, referrals or any business data.
--
-- Access: super admin by default; other admins only via an explicit grant.
-- Enforced in the DB (RLS + ai_decision_room_allowed) AND the edge function.
-- No AI provider ever gets DB access; only backend-computed aggregate metrics
-- (no PII) are optionally attached.
-- ============================================================================

-- Config / feature flag + limits + super-admin designation.
INSERT INTO public.app_config (key, value) VALUES
  ('ai_decision_room_enabled',   'true'),
  ('ai_decision_daily_limit',    '20'),               -- per user per day
  ('ai_decision_super_admin_email','support@7-dash.com'),
  ('ai_decision_synth_model',    'openai')            -- which side synthesizes
ON CONFLICT (key) DO NOTHING;

-- Explicit per-admin grants (beyond the super admin).
CREATE TABLE IF NOT EXISTS public.ai_decision_permissions (
  user_id    uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  granted_by uuid REFERENCES public.users(id),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ai_decision_permissions ENABLE ROW LEVEL SECURITY;

-- Authorization: is this (admin) user allowed into the AI Decision Room?
CREATE OR REPLACE FUNCTION public.ai_decision_room_allowed(p_user uuid DEFAULT auth.uid())
  RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT
    coalesce((SELECT value IN ('true','1') FROM public.app_config WHERE key='ai_decision_room_enabled'), false)
    AND EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_user AND u.role = 'admin')
    AND (
      -- super admin by email
      EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_user
              AND lower(u.email) = lower(coalesce(
                (SELECT value FROM public.app_config WHERE key='ai_decision_super_admin_email'),'')))
      OR EXISTS (SELECT 1 FROM public.ai_decision_permissions g WHERE g.user_id = p_user)
    );
$$;
GRANT EXECUTE ON FUNCTION public.ai_decision_room_allowed(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_ai_decision_super_admin(p_user uuid DEFAULT auth.uid())
  RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.users u WHERE u.id = p_user AND u.role='admin'
    AND lower(u.email) = lower(coalesce(
      (SELECT value FROM public.app_config WHERE key='ai_decision_super_admin_email'),'')));
$$;
GRANT EXECUTE ON FUNCTION public.is_ai_decision_super_admin(uuid) TO authenticated, service_role;

-- Decisions.
CREATE TABLE IF NOT EXISTS public.ai_decisions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_scope text NOT NULL DEFAULT 'hotbite',
  created_by     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  title          text NOT NULL,
  question       text NOT NULL,
  context        text,
  options        jsonb NOT NULL DEFAULT '[]'::jsonb,
  goals          text,
  budget         text,
  constraints    text,
  category       text NOT NULL DEFAULT 'other',  -- operations|pricing|marketing|restaurants|grocery|membership|technology|other
  include_metrics boolean NOT NULL DEFAULT false,
  metrics_snapshot jsonb,                         -- backend-computed aggregates only (no PII)
  synth_model    text NOT NULL DEFAULT 'openai',
  status         text NOT NULL DEFAULT 'draft',
  -- draft -> assessing -> cross_review -> synthesizing -> completed | failed | cancelled
  result         jsonb,                           -- final structured report
  final_choice   text,                            -- the admin's own decision (advisory record)
  final_notes    text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  completed_at   timestamptz
);
ALTER TABLE public.ai_decisions ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_ai_dec_creator ON public.ai_decisions(created_by);
CREATE INDEX IF NOT EXISTS idx_ai_dec_status  ON public.ai_decisions(status);

-- Durable per-stage workflow state (progress, retry, cancellation).
CREATE TABLE IF NOT EXISTS public.ai_decision_stages (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  decision_id uuid NOT NULL REFERENCES public.ai_decisions(id) ON DELETE CASCADE,
  stage       text NOT NULL,   -- openai_assess|claude_assess|openai_review|claude_review|synthesis
  provider    text NOT NULL,   -- openai|anthropic|mock
  status      text NOT NULL DEFAULT 'pending', -- pending|running|done|failed
  seq         int  NOT NULL,
  output      jsonb,
  error       text,
  tokens_in   int,
  tokens_out  int,
  started_at  timestamptz,
  finished_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (decision_id, stage)
);
ALTER TABLE public.ai_decision_stages ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_ai_stage_dec ON public.ai_decision_stages(decision_id);

-- ── RLS: creator (if still allowed) + super admin; writes via service/RPC ────
DROP POLICY IF EXISTS ai_dec_select ON public.ai_decisions;
CREATE POLICY ai_dec_select ON public.ai_decisions FOR SELECT TO authenticated
  USING (public.ai_decision_room_allowed()
         AND (created_by = auth.uid() OR public.is_ai_decision_super_admin()));
DROP POLICY IF EXISTS ai_dec_insert ON public.ai_decisions;
CREATE POLICY ai_dec_insert ON public.ai_decisions FOR INSERT TO authenticated
  WITH CHECK (public.ai_decision_room_allowed() AND created_by = auth.uid());
DROP POLICY IF EXISTS ai_dec_update ON public.ai_decisions;
CREATE POLICY ai_dec_update ON public.ai_decisions FOR UPDATE TO authenticated
  USING (public.ai_decision_room_allowed()
         AND (created_by = auth.uid() OR public.is_ai_decision_super_admin()));

DROP POLICY IF EXISTS ai_stage_select ON public.ai_decision_stages;
CREATE POLICY ai_stage_select ON public.ai_decision_stages FOR SELECT TO authenticated
  USING (public.ai_decision_room_allowed() AND EXISTS (
    SELECT 1 FROM public.ai_decisions d WHERE d.id = decision_id
      AND (d.created_by = auth.uid() OR public.is_ai_decision_super_admin())));

DROP POLICY IF EXISTS ai_perm_select ON public.ai_decision_permissions;
CREATE POLICY ai_perm_select ON public.ai_decision_permissions FOR SELECT TO authenticated
  USING (public.is_ai_decision_super_admin() OR user_id = auth.uid());

NOTIFY pgrst, 'reload schema';
