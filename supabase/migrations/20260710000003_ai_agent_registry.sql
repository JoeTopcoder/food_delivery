-- ─────────────────────────────────────────────────────────────────────────────
-- AI Agent Registry — foundation for the 7Dash AI Operations hub.
-- Every agent this platform runs gets one row here. The admin app's AI
-- Operations screen lists agents from this table and their run history from
-- the existing ai_agent_runs audit table. The status column is enforced
-- server-side by each agent's edge function (not just cosmetic in the UI).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.ai_agents (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug        text NOT NULL UNIQUE,
  name        text NOT NULL,
  department  text NOT NULL,
  description text,
  status      text NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'paused')),
  model       text,
  route       text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ai_agents ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_agents_select_admin" ON public.ai_agents;
CREATE POLICY "ai_agents_select_admin"
  ON public.ai_agents FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

DROP POLICY IF EXISTS "ai_agents_update_admin" ON public.ai_agents;
CREATE POLICY "ai_agents_update_admin"
  ON public.ai_agents FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS ai_agents_updated_at ON public.ai_agents;
CREATE TRIGGER ai_agents_updated_at
  BEFORE UPDATE ON public.ai_agents
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

INSERT INTO public.ai_agents (slug, name, department, description, model, route)
VALUES (
  'support_agent',
  'Customer Support Agent',
  'Customer Support',
  'Drafts replies and a suggested resolution (reply only / wallet credit / escalate) for incoming support tickets. Never sends a reply or moves money without admin approval.',
  'gpt-4o-mini',
  '/admin-support-requests'
)
ON CONFLICT (slug) DO NOTHING;
