-- ─────────────────────────────────────────────────────────────────────────────
-- Workflow Station — scheduled automation pipelines (pg_cron + edge function),
-- the native-Supabase equivalent of an n8n workflow: trigger → real data pull
-- → AI generation → draft storage → human review, with no auto-publish step
-- anywhere (matches every other agent this session — drafts always require
-- an admin to approve before anything goes out).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.automation_workflows (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug              text NOT NULL UNIQUE,
  name              text NOT NULL,
  description       text,
  schedule_cron     text NOT NULL,
  is_active         boolean NOT NULL DEFAULT true,
  last_run_at       timestamptz,
  last_run_status   text CHECK (last_run_status IN ('success', 'failed')),
  last_run_summary  text,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.automation_workflows ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "automation_workflows_admin_all" ON public.automation_workflows;
CREATE POLICY "automation_workflows_admin_all"
  ON public.automation_workflows FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE users.id = auth.uid() AND users.role = 'admin')
  );

CREATE TABLE IF NOT EXISTS public.marketing_content (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workflow_id   uuid REFERENCES public.automation_workflows(id) ON DELETE SET NULL,
  content_type  text NOT NULL DEFAULT 'social',
  captions      jsonb NOT NULL DEFAULT '[]'::jsonb,
  image_url     text,
  source_data   jsonb NOT NULL DEFAULT '{}'::jsonb,
  status        text NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft', 'approved', 'rejected', 'posted')),
  reviewed_by   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  reviewed_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.marketing_content ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "marketing_content_admin_all" ON public.marketing_content;
CREATE POLICY "marketing_content_admin_all"
  ON public.marketing_content FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE users.id = auth.uid() AND users.role = 'admin')
  );

CREATE INDEX IF NOT EXISTS idx_marketing_content_status ON public.marketing_content(status);
CREATE INDEX IF NOT EXISTS idx_marketing_content_created_at ON public.marketing_content(created_at DESC);

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS automation_workflows_updated_at ON public.automation_workflows;
CREATE TRIGGER automation_workflows_updated_at
  BEFORE UPDATE ON public.automation_workflows
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Storage bucket for generated promo images (OpenAI image URLs expire after
-- ~2 hours — we download and re-host so drafts stay viewable in the app).
INSERT INTO storage.buckets (id, name, public)
VALUES ('marketing-content', 'marketing-content', true)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "marketing_content_bucket_public_read" ON storage.objects;
CREATE POLICY "marketing_content_bucket_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'marketing-content');

DROP POLICY IF EXISTS "marketing_content_bucket_service_write" ON storage.objects;
CREATE POLICY "marketing_content_bucket_service_write"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'marketing-content' AND auth.role() = 'service_role');

INSERT INTO public.automation_workflows (slug, name, description, schedule_cron, is_active)
VALUES (
  'weekly_social_campaign',
  'Weekly Social Media Campaign',
  'Every Monday 9am: pulls popular menu items from real order data, generates 3 ready-to-post captions and a promo image, stores a draft, and emails admins for review. Falls back to a generic brand promo if no order data exists yet. Nothing is posted automatically.',
  '0 9 * * 1',
  true
)
ON CONFLICT (slug) DO NOTHING;

-- ── pg_cron job ──────────────────────────────────────────────────────────
-- The bearer secret is read from Supabase Vault (vault.decrypted_secrets),
-- NOT hardcoded here. ALTER DATABASE ... SET requires superuser, which
-- hosted Supabase doesn't grant — Vault is the correct mechanism. Set the
-- secret separately with:
--   SELECT vault.create_secret('<value>', 'automation_runner_secret', '...');
SELECT cron.unschedule('weekly-social-campaign')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly-social-campaign');

SELECT cron.schedule(
  'weekly-social-campaign',
  '0 9 * * 1',
  $$
  SELECT net.http_post(
    url := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/automation-workflow-runner',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'automation_runner_secret'),
      'Content-Type', 'application/json'
    ),
    body := '{"workflow_slug": "weekly_social_campaign"}'::jsonb
  ) AS request_id;
  $$
);
