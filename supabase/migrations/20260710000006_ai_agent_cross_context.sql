-- ─────────────────────────────────────────────────────────────────────────────
-- Cross-agent shared memory. Instead of a message bus, agents share context
-- through the audit trail they already write to: a run can tag every entity
-- it touched (order/driver/restaurant/user, not just its primary ticket/etc.),
-- so any other agent can later ask "what has already been observed about
-- this order/driver/restaurant/user" and factor it in before acting.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.ai_agent_runs
  ADD COLUMN IF NOT EXISTS related_entities jsonb NOT NULL DEFAULT '[]'::jsonb;

CREATE INDEX IF NOT EXISTS idx_ai_agent_runs_related_entities
  ON public.ai_agent_runs USING gin (related_entities);
