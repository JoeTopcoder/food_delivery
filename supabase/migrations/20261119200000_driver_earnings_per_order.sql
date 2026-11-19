-- Per-order driver earnings ledger. The advanced earnings screen reads
-- `driver_earnings`, but nothing ever populated it (0 rows) → drivers always saw
-- "No earnings for this period." This adds a trigger that writes one row per
-- delivered order, and backfills existing delivered orders.
-- base_pay = delivery_fee * driver_pay_percent (app_config, default 0.80);
-- tip = driver_tip; total_payout = base + tip.

CREATE UNIQUE INDEX IF NOT EXISTS driver_earnings_order_uniq
  ON public.driver_earnings(order_id) WHERE order_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.award_driver_earnings_on_delivery()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE
  v_rate numeric; v_base numeric; v_tip numeric; v_mins numeric; v_dist numeric; v_earned timestamptz;
BEGIN
  IF NEW.status = 'delivered' AND COALESCE(OLD.status,'') <> 'delivered' AND NEW.driver_id IS NOT NULL THEN
    IF EXISTS (SELECT 1 FROM public.driver_earnings WHERE order_id = NEW.id) THEN RETURN NEW; END IF;
    SELECT COALESCE((SELECT value::numeric FROM public.app_config WHERE key='driver_pay_percent'), 0.80) INTO v_rate;
    v_base := ROUND((COALESCE(NEW.delivery_fee,0)::numeric) * v_rate, 2);
    v_tip  := ROUND(COALESCE(NEW.driver_tip,0)::numeric, 2);
    v_dist := COALESCE(NEW.distance_km,0)::numeric;
    v_earned := COALESCE(NEW.delivered_at, NEW.completed_at, now());
    v_mins := GREATEST(0, EXTRACT(EPOCH FROM (v_earned - COALESCE(NEW.ordered_at, NEW.created_at, v_earned)))::numeric / 60.0);
    INSERT INTO public.driver_earnings
      (driver_id, order_id, base_pay, tip, total_payout, distance_km, duration_minutes, earnings_per_hour, earnings_per_km, earned_at)
    VALUES
      (NEW.driver_id, NEW.id, v_base, v_tip, v_base + v_tip, v_dist, ROUND(v_mins,1),
       CASE WHEN v_mins > 0 THEN ROUND((v_base + v_tip) / (v_mins/60.0), 2) ELSE 0 END,
       CASE WHEN v_dist > 0 THEN ROUND((v_base + v_tip) / v_dist, 2) ELSE 0 END,
       v_earned);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_award_driver_earnings ON public.orders;
CREATE TRIGGER trg_award_driver_earnings
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.award_driver_earnings_on_delivery();

INSERT INTO public.driver_earnings
  (driver_id, order_id, base_pay, tip, total_payout, distance_km, duration_minutes, earnings_per_hour, earnings_per_km, earned_at)
SELECT
  o.driver_id, o.id,
  ROUND((COALESCE(o.delivery_fee,0)::numeric) * COALESCE((SELECT value::numeric FROM public.app_config WHERE key='driver_pay_percent'),0.80), 2),
  ROUND(COALESCE(o.driver_tip,0)::numeric,2),
  ROUND((COALESCE(o.delivery_fee,0)::numeric) * COALESCE((SELECT value::numeric FROM public.app_config WHERE key='driver_pay_percent'),0.80), 2) + ROUND(COALESCE(o.driver_tip,0)::numeric,2),
  COALESCE(o.distance_km,0)::numeric,
  GREATEST(0, ROUND(EXTRACT(EPOCH FROM (COALESCE(o.delivered_at,o.completed_at,o.ordered_at,o.created_at) - COALESCE(o.ordered_at,o.created_at)))::numeric/60.0, 1)),
  0, 0,
  COALESCE(o.delivered_at, o.completed_at, o.ordered_at, o.created_at)
FROM public.orders o
WHERE o.status='delivered' AND o.driver_id IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM public.driver_earnings de WHERE de.order_id = o.id);

NOTIFY pgrst, 'reload schema';
