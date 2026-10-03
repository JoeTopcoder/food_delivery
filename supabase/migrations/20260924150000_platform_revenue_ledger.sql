-- Platform revenue ledger — an itemized accounting record of what HotBite keeps
-- on each delivered order, so platform revenue (including the HotBite+ Shared
-- Member Savings share) is explicit rather than only implied by "customer paid
-- minus partner payouts". This is NOT a payout ledger (nothing here is paid out
-- to anyone), so it deliberately does NOT live in earnings_ledger, which only
-- tracks driver/restaurant payouts with hold periods.
--
-- Per delivered order it records the four platform revenue components, matching
-- the canonical definition in get_financial_statistics():
--   restaurant_commission        = orders.commission_amount (on subtotal)
--   delivery_fee_platform_share  = delivery_fee * (1 - driver_pay_percent)
--   hotbite_savings_share        = orders.hotbite_savings_share (HotBite's 50% of the member saving)
--   service_fee                  = orders.platform_service_fee
-- total = sum of the four.

CREATE TABLE IF NOT EXISTS public.platform_revenue_ledger (
  id                          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id                    uuid NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
  restaurant_id               uuid,
  source                      text NOT NULL DEFAULT 'food',   -- food | grocery
  restaurant_commission       numeric NOT NULL DEFAULT 0,
  delivery_fee_platform_share numeric NOT NULL DEFAULT 0,
  hotbite_savings_share       numeric NOT NULL DEFAULT 0,
  service_fee                 numeric NOT NULL DEFAULT 0,
  total                       numeric NOT NULL DEFAULT 0,
  currency                    text NOT NULL DEFAULT 'JMD',
  recorded_at                 timestamptz NOT NULL DEFAULT now(),
  metadata                    jsonb NOT NULL DEFAULT '{}'::jsonb
);

CREATE INDEX IF NOT EXISTS idx_platform_revenue_recorded_at ON public.platform_revenue_ledger(recorded_at);
CREATE INDEX IF NOT EXISTS idx_platform_revenue_restaurant  ON public.platform_revenue_ledger(restaurant_id);

ALTER TABLE public.platform_revenue_ledger ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS platform_revenue_admin_select ON public.platform_revenue_ledger;
CREATE POLICY platform_revenue_admin_select ON public.platform_revenue_ledger FOR SELECT
  USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'admin'));

-- Idempotent recorder: writes exactly one row per order. Safe to call more than
-- once (e.g. a retried delivery completion) — the UNIQUE(order_id) + ON CONFLICT
-- makes the second call a no-op. Service-role only.
CREATE OR REPLACE FUNCTION public.record_platform_revenue(p_order_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  o           orders%ROWTYPE;
  v_driver_pct numeric;
  v_commission numeric;
  v_delivery_share numeric;
  v_hbshare   numeric;
  v_sfee      numeric;
  v_total     numeric;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id;
  END IF;

  SELECT COALESCE(NULLIF(value,'')::numeric, 0.80) INTO v_driver_pct
    FROM app_config WHERE key = 'driver_pay_percent';
  v_driver_pct := COALESCE(v_driver_pct, 0.80);

  v_commission     := COALESCE(o.commission_amount,
                        COALESCE(o.subtotal,0) * COALESCE(o.commission_rate,0))::numeric;
  v_delivery_share := (COALESCE(o.delivery_fee,0) * (1 - v_driver_pct))::numeric;
  v_hbshare        := COALESCE(o.hotbite_savings_share,0)::numeric;
  v_sfee           := COALESCE(o.platform_service_fee,0)::numeric;
  v_total          := ROUND(v_commission + v_delivery_share + v_hbshare + v_sfee, 2);

  INSERT INTO public.platform_revenue_ledger (
    order_id, restaurant_id, restaurant_commission,
    delivery_fee_platform_share, hotbite_savings_share, service_fee, total)
  VALUES (
    p_order_id, o.restaurant_id, ROUND(v_commission,2),
    ROUND(v_delivery_share,2), ROUND(v_hbshare,2), ROUND(v_sfee,2), v_total)
  ON CONFLICT (order_id) DO NOTHING;

  RETURN jsonb_build_object('order_id', p_order_id, 'total', v_total,
                            'hotbite_savings_share', ROUND(v_hbshare,2));
END;
$$;

REVOKE ALL ON FUNCTION public.record_platform_revenue(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.record_platform_revenue(uuid) TO service_role;

-- Admin read: platform revenue totals over a window, plus the HotBite-share slice.
CREATE OR REPLACE FUNCTION public.admin_platform_revenue(
  p_from timestamptz,
  p_to   timestamptz
)
RETURNS TABLE (
  entries                     bigint,
  restaurant_commission       numeric,
  delivery_fee_platform_share numeric,
  hotbite_savings_share       numeric,
  service_fee                 numeric,
  total                       numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN QUERY
  SELECT count(*)::bigint,
         ROUND(COALESCE(sum(l.restaurant_commission),0),2),
         ROUND(COALESCE(sum(l.delivery_fee_platform_share),0),2),
         ROUND(COALESCE(sum(l.hotbite_savings_share),0),2),
         ROUND(COALESCE(sum(l.service_fee),0),2),
         ROUND(COALESCE(sum(l.total),0),2)
  FROM public.platform_revenue_ledger l
  WHERE l.recorded_at >= p_from AND l.recorded_at < p_to;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_platform_revenue(timestamptz,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_platform_revenue(timestamptz,timestamptz) TO authenticated;

-- Backfill: record revenue for already-delivered orders so the ledger is
-- complete from day one. Idempotent (ON CONFLICT DO NOTHING inside the fn).
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM orders WHERE status = 'delivered' LOOP
    PERFORM public.record_platform_revenue(r.id);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
