-- ─────────────────────────────────────────────────────────────────────────────
-- Restaurant Leads — manual-entry CRM for the Restaurant Lead Gen / Sales
-- agents. This app has no external business-data API (Google Places, Yelp,
-- etc.), so leads are entered by an admin who's identified a prospect
-- themselves — the agents score/dedupe/draft outreach for real leads,
-- never fabricate them.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.restaurant_leads (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  contact_name  text,
  phone         text,
  email         text,
  address       text,
  cuisine_type  text,
  source        text,
  notes         text,
  status        text NOT NULL DEFAULT 'new'
                  CHECK (status IN ('new', 'contacted', 'qualified', 'converted', 'rejected')),
  score         numeric,
  ai_draft_outreach text,
  ai_status     text
                  CHECK (ai_status IN ('drafted', 'approved', 'rejected', 'sent')),
  ai_run_id     uuid REFERENCES public.ai_agent_runs(id) ON DELETE SET NULL,
  created_by    uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_by   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.restaurant_leads ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "restaurant_leads_admin_all" ON public.restaurant_leads;
CREATE POLICY "restaurant_leads_admin_all"
  ON public.restaurant_leads FOR ALL
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

DROP TRIGGER IF EXISTS restaurant_leads_updated_at ON public.restaurant_leads;
CREATE TRIGGER restaurant_leads_updated_at
  BEFORE UPDATE ON public.restaurant_leads
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_restaurant_leads_status ON public.restaurant_leads(status);
CREATE INDEX IF NOT EXISTS idx_restaurant_leads_created_at ON public.restaurant_leads(created_at DESC);
