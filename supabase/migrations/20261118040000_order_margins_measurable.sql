-- Delivery Margins marked almost every order "unmeasurable" because it required
-- driver pay, processor fee AND commission to each be stored and > 0. In reality:
--   • commission is 0 for stores with commission_rate = 0 (they monetise via
--     delivery + service fee) — a known zero, not missing data;
--   • processor fee is 0 for cash orders — known, not missing;
--   • driver pay is derivable from the delivery fee (driver gets driver_pay_percent
--     of it) when not explicitly recorded.
-- So the margins were actually correct; only the "measurable" test was wrong. This
-- aligns the RPC with the derivation used everywhere else (economics / accounting /
-- financial statistics): an order is measurable when it has a real charge and
-- subtotal; commission/processor/driver pay are derived consistently.
CREATE OR REPLACE FUNCTION public.admin_order_margins(p_limit integer DEFAULT 100, p_days integer DEFAULT 90)
 RETURNS TABLE(order_id uuid, created_at timestamp with time zone, status text,
   restaurant_name text, subtotal numeric, delivery_fee numeric, service_fee numeric,
   charged numeric, commission numeric, restaurant_paid numeric, driver_paid numeric,
   stripe_fee numeric, tip numeric, net_profit numeric, margin_pct numeric,
   data_complete boolean, missing_fields text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_driver_pct numeric;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  v_driver_pct := COALESCE(
    (SELECT NULLIF(value,'')::numeric FROM app_config WHERE key='driver_pay_percent'), 0.80);

  RETURN QUERY
  WITH base AS (
    SELECT o.id, o.created_at, o.status, r.name AS restaurant_name,
           COALESCE(o.subtotal, 0)              AS subtotal,
           COALESCE(o.delivery_fee, 0)          AS delivery_fee,
           COALESCE(o.total_amount, 0)          AS total_amount,
           lower(COALESCE(o.payment_method,'')) AS pay_method,
           COALESCE(o.driver_tip, 0) + COALESCE(o.post_delivery_tip, 0) AS tip,
           -- Commission: stored, else subtotal * rate (0 when no rate — a real 0).
           COALESCE(o.commission_amount,
                    COALESCE(o.subtotal,0) * COALESCE(o.commission_rate, 0)) AS commission,
           -- Service fee: stored, else the residual that reconciles the total.
           CASE WHEN o.platform_service_fee IS NOT NULL THEN o.platform_service_fee
                ELSE GREATEST(COALESCE(o.total_amount,0) - COALESCE(o.subtotal,0)
                     - COALESCE(o.delivery_fee,0) - COALESCE(o.tax_amount,0)
                     - COALESCE(o.driver_tip,0)
                     + GREATEST(COALESCE(o.discount,0), COALESCE(o.discount_amount,0)), 0)
           END AS service_fee,
           o.driver_total_pay,
           o.stripe_fee_amount
    FROM public.orders o
    LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
    WHERE o.created_at > now() - (p_days || ' days')::interval
  ),
  calc AS (
    SELECT b.*,
           (b.total_amount - b.tip) AS charged_ex_tip,
           (b.subtotal - b.commission) AS restaurant_paid,
           -- Driver delivery pay (ex-tip): recorded, else derived from the fee.
           GREATEST(
             COALESCE(NULLIF(b.driver_total_pay,0), b.delivery_fee * v_driver_pct + b.tip) - b.tip,
             0) AS driver_paid_ex_tip,
           -- Processor: 0 for cash, stored fee, else a card estimate.
           CASE
             WHEN b.pay_method IN ('cash','cash_on_delivery','cod') THEN 0
             WHEN b.stripe_fee_amount IS NOT NULL THEN b.stripe_fee_amount
             WHEN b.pay_method IN ('stripe','card','credit_card','debit_card')
               THEN ROUND((b.subtotal * 0.029 + 0.30)::numeric, 2)
             ELSE 0
           END AS processor
    FROM base b
  )
  SELECT c.id, c.created_at, c.status, c.restaurant_name,
         ROUND(c.subtotal::numeric, 2), ROUND(c.delivery_fee::numeric, 2),
         ROUND(c.service_fee::numeric, 2), ROUND(c.charged_ex_tip::numeric, 2),
         ROUND(c.commission::numeric, 2), ROUND(c.restaurant_paid::numeric, 2),
         ROUND(c.driver_paid_ex_tip::numeric, 2), ROUND(c.processor::numeric, 2),
         ROUND(c.tip::numeric, 2),
         ROUND((c.charged_ex_tip - c.restaurant_paid - c.driver_paid_ex_tip - c.processor)::numeric, 2),
         CASE WHEN c.charged_ex_tip > 0
              THEN ROUND((((c.charged_ex_tip - c.restaurant_paid - c.driver_paid_ex_tip - c.processor)
                          / c.charged_ex_tip) * 100)::numeric, 1)
              ELSE NULL END,
         -- Measurable when there is a real charge and subtotal; everything else
         -- is derived consistently with the rest of the platform's financials.
         (c.charged_ex_tip > 0 AND c.subtotal > 0),
         NULLIF(CONCAT_WS(', ',
           CASE WHEN c.subtotal <= 0       THEN 'order subtotal' END,
           CASE WHEN c.charged_ex_tip <= 0 THEN 'amount charged' END
         ), '')
  FROM calc c
  ORDER BY c.created_at DESC
  LIMIT p_limit;
END;
$function$;

NOTIFY pgrst, 'reload schema';
