-- ============================================================================
-- Rebrand remaining old-brand strings in the LIVE database to HotBite.
-- These are the only in-app brand leaks left (Dart/app code is already clean):
--   • app_config.support_email       = 'support@7-dash.com'   -> support@hotbite.app
--   • app_config.grocery_public_brand = 'Quickdash Groceries'  -> HotBite Groceries
--   • 4 user-facing functions whose message text still says "QuickDash":
--       enqueue_whatsapp_order_update, generate_targeted_coupon,
--       notify_customer_on_ride_status_change, wallet_transfer
-- Function bodies are rebranded by string-replacing brand tokens that only ever
-- appear inside user-facing string literals in these functions (verified), then
-- re-executing the definition -- the same approach as the earlier
-- 20260908000002_rebrand_notification_text migration.
-- ============================================================================

-- 1. Config values -----------------------------------------------------------
UPDATE public.app_config SET value = 'support@hotbite.app', updated_at = now()
  WHERE key = 'support_email';
UPDATE public.app_config SET value = 'HotBite Groceries', updated_at = now()
  WHERE key = 'grocery_public_brand';

-- 2. User-facing function text ----------------------------------------------
DO $rebrand$
DECLARE
  r record;
  v_def text;
  v_new text;
BEGIN
  FOR r IN
    SELECT p.oid
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prokind = 'f'
      AND p.proname IN ('enqueue_whatsapp_order_update','generate_targeted_coupon',
                        'notify_customer_on_ride_status_change','wallet_transfer')
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := v_def;
    v_new := replace(v_new, 'QuickDash',  'HotBite');
    v_new := replace(v_new, 'Quickdash',  'HotBite');
    v_new := replace(v_new, 'quickdash',  'hotbite');
    v_new := replace(v_new, 'MealHub',    'HotBite');
    v_new := replace(v_new, '7Dash',      'HotBite');
    v_new := replace(v_new, '7-dash',     'hotbite');
    IF v_new <> v_def THEN
      EXECUTE v_new;
    END IF;
  END LOOP;
END;
$rebrand$;

NOTIFY pgrst, 'reload schema';
