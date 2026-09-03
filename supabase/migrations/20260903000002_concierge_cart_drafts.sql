-- Migration: concierge cart drafts + session log
--
-- The concierge tool contract passes a `cart_draft_id` between calls
-- (build_cart_draft -> price_cart -> get_eligible_promotions -> apply_promotion
-- -> finalize_cart -> handoff_to_checkout). The app's real cart is client-side
-- SharedPreferences with no server table, so a draft needs somewhere to live
-- for the duration of that exchange.
--
-- A draft is explicitly NOT an order and NOT the customer's cart. It is a
-- proposal the concierge assembles and prices; nothing reaches the real cart
-- until the customer confirms on the review screen, and nothing is charged
-- until they complete the existing checkout.

CREATE TABLE IF NOT EXISTS public.concierge_cart_drafts (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id  UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,

  -- [{ item_id, name, qty, unit_price_cents, modifiers: [] }]
  -- Prices are snapshotted at build time and re-validated against the live menu
  -- in price_cart, so a stale draft can never carry an out-of-date price into
  -- checkout.
  line_items     JSONB NOT NULL DEFAULT '[]'::jsonb,

  applied_promo_code TEXT,

  -- draft   : still being assembled/priced
  -- finalized: locked by finalize_cart, ready to hand to checkout
  -- consumed : handed off; no further edits
  status         TEXT NOT NULL DEFAULT 'draft'
                 CHECK (status IN ('draft','finalized','consumed')),

  -- What the customer actually asked for, kept for observability and so a
  -- follow-up turn ("make it less spicy") has the original constraints.
  constraints    JSONB,

  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_concierge_drafts_user
  ON public.concierge_cart_drafts (user_id, created_at DESC);

ALTER TABLE public.concierge_cart_drafts ENABLE ROW LEVEL SECURITY;

-- A customer may only ever see and touch their own drafts. The edge function
-- runs as service_role and bypasses this, but it checks ownership itself on
-- every tool call before acting.
DROP POLICY IF EXISTS concierge_drafts_own ON public.concierge_cart_drafts;
CREATE POLICY concierge_drafts_own ON public.concierge_cart_drafts
  FOR ALL USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ── Session log ─────────────────────────────────────────────────────────────
-- Observability for a feature that spends money and makes dietary claims: what
-- was asked, what constraints were parsed, which tools ran, what was proposed.
CREATE TABLE IF NOT EXISTS public.concierge_sessions (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        UUID REFERENCES public.users(id) ON DELETE SET NULL,
  request_text   TEXT,
  parsed_constraints JSONB,
  tool_calls     JSONB,
  cart_draft_id  UUID REFERENCES public.concierge_cart_drafts(id) ON DELETE SET NULL,
  outcome        TEXT,
  error          TEXT,
  latency_ms     INTEGER,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_concierge_sessions_user
  ON public.concierge_sessions (user_id, created_at DESC);

ALTER TABLE public.concierge_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS concierge_sessions_own ON public.concierge_sessions;
CREATE POLICY concierge_sessions_own ON public.concierge_sessions
  FOR SELECT USING (user_id = auth.uid());

NOTIFY pgrst, 'reload schema';
