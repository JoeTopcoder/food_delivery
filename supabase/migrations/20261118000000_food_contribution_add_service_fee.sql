-- Fix: admin_metrics_food omitted the platform service fee from contribution.
-- Food orders charge a service fee (orders.platform_service_fee) that is pure
-- platform revenue, yet contribution was commission + delivery_fee - rider_payout
-- only. admin_metrics_grocery already folds service_fee in (agg.s + ...); food now
-- matches. admin_metrics_combined sums the two, so the dashboard total follows.
-- Return signature is unchanged (service_fee is folded into contribution_total,
-- not added as a new column), so no app/model change is needed.
CREATE OR REPLACE FUNCTION public.admin_metrics_food(
  p_period text DEFAULT 'today'::text,
  p_from timestamp with time zone DEFAULT NULL::timestamp with time zone,
  p_to timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS TABLE(orders_count bigint, gmv bigint, restaurant_commission_total bigint,
   delivery_fee_total bigint, rider_payout_total bigint, contribution_total bigint,
   avg_order_value bigint, breakeven_orders_required bigint, breakeven_progress_pct numeric)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_from TIMESTAMPTZ;
  v_to   TIMESTAMPTZ;
  v_ops  NUMERIC;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  SELECT * INTO v_from, v_to
    FROM public.admin_period_range(p_period, p_from, p_to);
  v_ops := COALESCE(
    (SELECT value FROM public.app_config WHERE key = 'monthly_ops_cost')::numeric, 0);

  RETURN QUERY
  WITH e AS (SELECT * FROM public.admin_order_economics(v_from, v_to, FALSE)),
  agg AS (
    SELECT count(*)::bigint                        AS n,
           COALESCE(sum(e.gmv), 0)::bigint          AS g,
           COALESCE(sum(e.commission), 0)::bigint   AS c,
           COALESCE(sum(e.delivery_fee), 0)::bigint AS d,
           COALESCE(sum(e.service_fee), 0)::bigint  AS s,
           COALESCE(sum(e.rider_payout), 0)::bigint AS p
    FROM e
  ),
  calc AS (
    SELECT agg.*,
           (agg.c + agg.d + agg.s - agg.p) AS contrib,
           -- Break-even orders = monthly ops cost / contribution per order.
           CASE WHEN v_ops > 0 AND agg.n > 0 AND (agg.c + agg.d + agg.s - agg.p) > 0
                THEN CEIL((v_ops * 100)
                     / ((agg.c + agg.d + agg.s - agg.p)::numeric / agg.n))::bigint
                ELSE 0::bigint END AS required
    FROM agg
  )
  SELECT calc.n, calc.g, calc.c, calc.d, calc.p, calc.contrib::bigint,
         CASE WHEN calc.n > 0 THEN (calc.g / calc.n)::bigint ELSE 0::bigint END,
         calc.required,
         CASE WHEN calc.required > 0
              THEN ROUND((calc.n::numeric / calc.required) * 100, 1)
              ELSE 0::numeric END
  FROM calc;
END;
$function$;

NOTIFY pgrst, 'reload schema';
