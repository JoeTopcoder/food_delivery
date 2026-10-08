-- ============================================================================
-- HotBite Restaurant Ads — go-live wiring
--  1. Auto-attribute orders to ad campaigns when they reach 'delivered'.
--  2. Enable the feature (flag + settings).
-- ============================================================================

-- 1) Attribution trigger: runs ad_attribute_order when an order becomes
--    delivered (last cta_click within 24h, same restaurant, one campaign, deduped).
--    Best-effort: never block the order update if attribution hits an edge case.
CREATE OR REPLACE FUNCTION public._ad_orders_attribution_trg()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status IN ('delivered','completed')
     AND NEW.status IS DISTINCT FROM OLD.status THEN
    BEGIN
      PERFORM public.ad_attribute_order(NEW.id);
    EXCEPTION WHEN OTHERS THEN
      -- attribution is non-critical; swallow so order completion never fails
      NULL;
    END;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS ad_orders_attribution ON public.orders;
CREATE TRIGGER ad_orders_attribution
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public._ad_orders_attribution_trg();

-- 2) Enable the feature (safe: get_sponsored_ads returns nothing until there are
--    eligible, paid, approved, in-schedule campaigns).
UPDATE public.ad_settings SET enabled = true, updated_at = now() WHERE id = 1;
UPDATE public.app_config SET value = 'true' WHERE key = 'restaurant_ads_enabled';

NOTIFY pgrst, 'reload schema';
