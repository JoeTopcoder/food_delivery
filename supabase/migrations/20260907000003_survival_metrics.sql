-- Migration: break-even and survival metrics
--
-- Splits cleanly into two kinds of number, and the dashboard must never blur
-- them:
--
--   MEASURED  - computed from real rows (orders, drivers, customers)
--   ASSUMED   - business inputs only the operator knows (rent, retainers,
--               fuel float, marketing spend, cash in the bank)
--
-- Break-even cannot be derived from orders alone, because fixed costs live
-- outside this system entirely. So the assumptions are stored as editable
-- config and the dashboard labels which figures rest on them.

INSERT INTO public.app_config (key, value, description)
VALUES
  ('biz_daily_fixed_costs',     '0',  'Costs paid daily regardless of order volume: retainers, insurance, fuel float, tooling.'),
  ('biz_variable_cost_order',   '0',  'Cost incurred per delivery beyond driver pay already recorded on the order (fuel, consumables).'),
  ('biz_monthly_marketing',     '0',  'Marketing spend per month, used for customer acquisition cost.'),
  ('biz_cash_reserve',          '0',  'Cash available to absorb losses, used to compute runway in days.'),
  ('biz_target_orders_per_day', '17', 'Break-even order target; recalculated from costs when they are set.')
ON CONFLICT (key) DO NOTHING;

CREATE OR REPLACE FUNCTION public.admin_survival_metrics(p_days INT DEFAULT 30)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_fixed        NUMERIC := COALESCE((SELECT value FROM app_config WHERE key='biz_daily_fixed_costs')::NUMERIC, 0);
  v_var_order    NUMERIC := COALESCE((SELECT value FROM app_config WHERE key='biz_variable_cost_order')::NUMERIC, 0);
  v_marketing    NUMERIC := COALESCE((SELECT value FROM app_config WHERE key='biz_monthly_marketing')::NUMERIC, 0);
  v_reserve      NUMERIC := COALESCE((SELECT value FROM app_config WHERE key='biz_cash_reserve')::NUMERIC, 0);

  v_orders       INT;
  v_delivered    INT;
  v_gmv          NUMERIC;
  v_aov          NUMERIC;
  v_days         NUMERIC := GREATEST(p_days, 1);
  v_orders_day   NUMERIC;
  v_customers    INT;
  v_new_cust     INT;
  v_drivers      INT;
  v_measurable   INT;
  v_avg_profit   NUMERIC;
  v_profit_order NUMERIC;
  v_breakeven    NUMERIC;
  v_daily_rev    NUMERIC;
  v_daily_cost   NUMERIC;
  v_burn         NUMERIC;
  v_runway       NUMERIC;
  v_cac          NUMERIC;
  v_ltv          NUMERIC;
  v_orders_cust  NUMERIC;
BEGIN
  SELECT count(*),
         count(*) FILTER (WHERE status = 'delivered'),
         COALESCE(SUM(total_amount), 0),
         count(DISTINCT user_id)
    INTO v_orders, v_delivered, v_gmv, v_customers
  FROM orders
  WHERE created_at > now() - (p_days || ' days')::interval;

  v_aov        := CASE WHEN v_orders > 0 THEN v_gmv / v_orders ELSE 0 END;
  v_orders_day := v_orders / v_days;

  -- Profit per order from orders that actually recorded their payouts. Orders
  -- missing driver pay or processor fees report wildly inflated margins, so
  -- they are excluded rather than averaged in.
  SELECT count(*), COALESCE(AVG(net_profit), 0)
    INTO v_measurable, v_avg_profit
  FROM admin_order_margins(500, p_days)
  WHERE data_complete;

  -- Fall back to the assumption when nothing is measurable, so break-even is
  -- still answerable; the dashboard flags which case it is.
  v_profit_order := CASE
    WHEN v_measurable > 0 THEN v_avg_profit - v_var_order
    ELSE GREATEST(v_aov * 0.15 - v_var_order, 0)
  END;

  v_breakeven  := CASE WHEN v_profit_order > 0 THEN v_fixed / v_profit_order ELSE NULL END;
  v_daily_rev  := (v_orders_day * COALESCE(NULLIF(v_avg_profit, 0), v_aov * 0.15));
  v_daily_cost := v_fixed + (v_orders_day * v_var_order);
  v_burn       := v_daily_cost - v_daily_rev;
  v_runway     := CASE WHEN v_burn > 0 THEN v_reserve / v_burn ELSE NULL END;

  SELECT count(*) INTO v_new_cust
  FROM users u
  WHERE u.created_at > now() - (p_days || ' days')::interval;

  v_cac := CASE WHEN v_new_cust > 0
                THEN (v_marketing * (v_days / 30.0)) / v_new_cust ELSE NULL END;

  v_orders_cust := CASE WHEN v_customers > 0 THEN v_orders::NUMERIC / v_customers ELSE 0 END;
  v_ltv := v_profit_order * v_orders_cust * 3;   -- 3 months assumed active

  SELECT count(DISTINCT driver_id) INTO v_drivers
  FROM orders
  WHERE driver_id IS NOT NULL
    AND created_at > now() - (p_days || ' days')::interval;

  RETURN jsonb_build_object(
    'window_days',        p_days,
    'orders',             v_orders,
    'delivered',          v_delivered,
    'orders_per_day',     ROUND(v_orders_day, 1),
    'gmv',                ROUND(v_gmv, 2),
    'aov',                ROUND(v_aov, 2),
    'fulfilment_pct',     CASE WHEN v_orders > 0
                               THEN ROUND(v_delivered::NUMERIC / v_orders * 100, 1) ELSE NULL END,
    'active_drivers',     v_drivers,
    'driver_utilisation', CASE WHEN v_drivers > 0
                               THEN ROUND(v_orders::NUMERIC / v_drivers / v_days, 1) ELSE NULL END,
    'measurable_orders',  v_measurable,
    'profit_per_order',   ROUND(v_profit_order, 2),
    'profit_is_measured', v_measurable > 0,
    'breakeven_orders',   CASE WHEN v_breakeven IS NULL THEN NULL ELSE CEIL(v_breakeven) END,
    'daily_revenue',      ROUND(v_daily_rev, 2),
    'daily_cost',         ROUND(v_daily_cost, 2),
    'burn_per_day',       ROUND(v_burn, 2),
    'runway_days',        CASE WHEN v_runway IS NULL THEN NULL ELSE FLOOR(v_runway) END,
    'new_customers',      v_new_cust,
    'cac',                CASE WHEN v_cac IS NULL THEN NULL ELSE ROUND(v_cac, 2) END,
    'ltv',                ROUND(v_ltv, 2),
    'ltv_to_cac',         CASE WHEN v_cac IS NULL OR v_cac = 0
                               THEN NULL ELSE ROUND(v_ltv / v_cac, 1) END,
    'orders_per_customer', ROUND(v_orders_cust, 1),
    'assumptions_set',    (v_fixed > 0 OR v_var_order > 0 OR v_marketing > 0 OR v_reserve > 0),
    'assumptions', jsonb_build_object(
      'daily_fixed_costs',   v_fixed,
      'variable_cost_order', v_var_order,
      'monthly_marketing',   v_marketing,
      'cash_reserve',        v_reserve
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_survival_metrics TO authenticated;

NOTIFY pgrst, 'reload schema';
