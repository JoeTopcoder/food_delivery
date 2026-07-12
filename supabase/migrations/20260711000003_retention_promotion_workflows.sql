-- ─────────────────────────────────────────────────────────────────────────────
-- Two more Workflow Station pipelines: weekly retention outreach drafting and
-- weekly promotion scanning. Same discipline as weekly_social_campaign —
-- trigger → real data pull → AI draft → human review. Nothing here sends an
-- email or creates a promo code by itself.
-- ─────────────────────────────────────────────────────────────────────────────

INSERT INTO public.automation_workflows (slug, name, description, schedule_cron, is_active)
VALUES (
  'weekly_retention_outreach',
  'Weekly Retention Outreach',
  'Every Monday 9:30am: finds customers who haven''t ordered in 21+ days, drafts a personalized win-back email for up to 5 of them (skipping anyone Fraud & Risk flagged or already contacted in the last 14 days), and emails admins to review. Nothing is sent automatically.',
  '30 9 * * 1',
  true
),
(
  'weekly_promotion_scan',
  'Weekly Promotion Scan',
  'Every Monday 10am: checks Marketing Strategy''s at-risk-restaurant signal and Customer Retention''s at-risk count; if there''s a real opportunity, drafts one promo code proposal and emails admins to review. Skips the week entirely if there''s no strong signal. Nothing is created automatically.',
  '0 10 * * 1',
  true
)
ON CONFLICT (slug) DO NOTHING;

SELECT cron.unschedule('weekly-retention-outreach')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly-retention-outreach');

SELECT cron.schedule(
  'weekly-retention-outreach',
  '30 9 * * 1',
  $$
  SELECT net.http_post(
    url := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/automation-workflow-runner',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'automation_runner_secret'),
      'Content-Type', 'application/json'
    ),
    body := '{"workflow_slug": "weekly_retention_outreach"}'::jsonb
  ) AS request_id;
  $$
);

SELECT cron.unschedule('weekly-promotion-scan')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly-promotion-scan');

SELECT cron.schedule(
  'weekly-promotion-scan',
  '0 10 * * 1',
  $$
  SELECT net.http_post(
    url := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/automation-workflow-runner',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'automation_runner_secret'),
      'Content-Type', 'application/json'
    ),
    body := '{"workflow_slug": "weekly_promotion_scan"}'::jsonb
  ) AS request_id;
  $$
);
