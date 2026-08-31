-- ─────────────────────────────────────────────────────────────────────────────
-- Birthday Celebration System.
--
-- Reward mechanism deliberately reuses public.promo_codes (minting a fresh
-- single-use code, same pattern as createRetentionPromoCode() in
-- automation-workflow-runner) rather than inventing a parallel redemption
-- engine — checkout already knows how to apply/validate any promo code.
-- birthday_rewards below is a lightweight LOG for idempotency + admin
-- reporting only; redemption truth always lives on the linked promo_codes
-- row (usage_count/is_active/expires_at), never duplicated here.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.users ADD COLUMN IF NOT EXISTS birthday DATE;

CREATE TABLE IF NOT EXISTS public.birthday_rewards (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  birthday_date         date NOT NULL,
  promo_code_id         uuid REFERENCES public.promo_codes(id) ON DELETE SET NULL,
  notification_sent     boolean NOT NULL DEFAULT false,
  notification_sent_at  timestamptz,
  created_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, birthday_date)
);

CREATE INDEX IF NOT EXISTS idx_birthday_rewards_user ON public.birthday_rewards(user_id);
CREATE INDEX IF NOT EXISTS idx_birthday_rewards_date ON public.birthday_rewards(birthday_date);

ALTER TABLE public.birthday_rewards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "birthday_rewards_self_read" ON public.birthday_rewards;
CREATE POLICY "birthday_rewards_self_read"
  ON public.birthday_rewards FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "birthday_rewards_admin_all" ON public.birthday_rewards;
CREATE POLICY "birthday_rewards_admin_all"
  ON public.birthday_rewards FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE users.id = auth.uid() AND users.role = 'admin')
  );

-- public.promo_codes SELECT is admin-only ("admin_select_promos",
-- 018_fix_admin_rls_comprehensive.sql) — customers only ever see promo data
-- through validate-promo's sanitized response, never the raw table. The
-- BirthdayRewardScreen needs to show a customer their OWN birthday code's
-- live status (used/expired), so add one narrowly-scoped additional
-- permissive policy: readable only when a birthday_rewards row links that
-- exact promo_codes row to the requesting user. This does not widen access
-- to any other promo_codes row.
DROP POLICY IF EXISTS "self_select_own_birthday_promo" ON public.promo_codes;
CREATE POLICY "self_select_own_birthday_promo"
  ON public.promo_codes FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.birthday_rewards br
      WHERE br.promo_code_id = promo_codes.id AND br.user_id = auth.uid()
    )
  );

-- ── Campaign settings (admin-editable, existing app_config pattern) ────────
INSERT INTO app_config (key, value, value_type, category, description) VALUES
  ('birthday_campaign_enabled',  'true',
   'boolean', 'birthday', 'Master on/off switch for the daily birthday campaign'),
  ('birthday_discount_amount',   '500',
   'number',  'birthday', 'Fixed-amount birthday discount, in the app''s configured currency'),
  ('birthday_min_order_amount',  '2000',
   'number',  'birthday', 'Minimum order subtotal required to use a birthday reward code'),
  ('birthday_notification_title','🎂 Happy Birthday!',
   'string',  'birthday', 'Push/in-app notification title for birthday wishes'),
  ('birthday_notification_body', 'Happy Birthday, {first_name}! 🎉 We''ve got a special reward waiting for you.',
   'string',  'birthday', 'Push/in-app notification body — {first_name} is replaced with the customer''s first name')
ON CONFLICT (key) DO NOTHING;

-- ── Workflow Station registration ───────────────────────────────────────────
-- auto_approve = true per product decision: this is a fixed, personalized
-- template with no AI-generated/creative content to review, unlike the other
-- marketing workflows — it sends automatically every morning.
INSERT INTO public.automation_workflows (slug, name, description, schedule_cron, is_active, auto_approve)
VALUES (
  'daily_birthday_wishes',
  'Daily Birthday Wishes',
  'Every day at 8am Cayman time: finds customers whose birthday is today, mints a one-time birthday discount code for each (respecting the Birthday Campaign settings), and sends a push + in-app notification. Idempotent — running it twice the same day does not create duplicate rewards.',
  '0 12 * * *',
  true,
  true
)
ON CONFLICT (slug) DO NOTHING;

-- 12:00 UTC = 08:00 Cayman time (fixed EST offset, no DST — same assumption
-- as lib/utils/est_datetime.dart).
SELECT cron.unschedule('daily-birthday-wishes')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'daily-birthday-wishes');

SELECT cron.schedule(
  'daily-birthday-wishes',
  '0 12 * * *',
  $$
  SELECT net.http_post(
    url := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/automation-workflow-runner',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'automation_runner_secret'),
      'Content-Type', 'application/json'
    ),
    body := '{"workflow_slug": "daily_birthday_wishes"}'::jsonb
  ) AS request_id;
  $$
);
