-- Super-admin accounting export: a per-order financial breakdown for a date
-- range, across BOTH food and grocery sales, so an admin can download a file
-- and file taxes easily. One row per delivered order with every figure an
-- accountant needs: goods price, delivery fee, service fee, GCT (tax) collected,
-- tip, discount, total charged, commission, restaurant payout, driver pay,
-- processor fee, and the platform profit.
--
-- Figures reconcile with the dashboard/financials model:
--   • processor (Stripe) fee is 0 for cash — cash never touches Stripe
--   • driver pay = what the delivery actually paid (driver_total_pay, incl. tip),
--     falling back to delivery_fee × driver_pay_percent + tip when not recorded
--   • restaurant payout = goods subtotal − commission
--   • platform profit  = total − restaurant payout − driver pay − processor fee
--                        − GCT (remitted to government, never profit)
CREATE OR REPLACE FUNCTION public.admin_accounting_rows(
  p_from timestamptz,
  p_to   timestamptz
)
RETURNS TABLE(
  order_date        timestamptz,
  receipt           text,
  order_type        text,
  store_name        text,
  payment_method    text,
  goods_subtotal    numeric,
  delivery_fee      numeric,
  service_fee       numeric,
  tax_gct           numeric,
  tip               numeric,
  discount          numeric,
  total_charged     numeric,
  commission        numeric,
  restaurant_payout numeric,
  driver_pay        numeric,
  processor_fee     numeric,
  platform_profit   numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_driver_pct numeric;
BEGIN
  -- Super-admin only: this exposes full financials across every store.
  IF NOT public.current_user_is_super_admin() THEN
    RAISE EXCEPTION 'Forbidden: super-admin access required';
  END IF;

  v_driver_pct := COALESCE(
    (SELECT NULLIF(value,'')::numeric FROM app_config WHERE key='driver_pay_percent'),
    0.80);

  RETURN QUERY
  WITH o AS (
    SELECT
      ord.*,
      r.name AS r_name,
      COALESCE(r.store_type,'food') AS r_store_type,
      GREATEST(COALESCE(ord.discount,0), COALESCE(ord.discount_amount,0)) AS coupon_discount,
      COALESCE(ord.commission_amount,
               COALESCE(ord.subtotal,0) * COALESCE(ord.commission_rate,0)) AS commission_v,
      -- Driver pay actually paid for this delivery (tips included); fall back to
      -- the configured delivery-fee share plus tip when it was never recorded.
      COALESCE(NULLIF(ord.driver_total_pay,0),
               COALESCE(ord.delivery_fee,0) * v_driver_pct + COALESCE(ord.driver_tip,0))
        AS driver_pay_v,
      -- Processor fee: 0 for cash; real stored fee; else a card estimate.
      CASE
        WHEN lower(COALESCE(ord.payment_method,'')) IN ('cash','cash_on_delivery','cod')
          THEN 0
        WHEN ord.stripe_fee_amount IS NOT NULL
          THEN ord.stripe_fee_amount
        WHEN lower(COALESCE(ord.payment_method,'')) IN ('stripe','card','credit_card','debit_card')
          THEN ROUND(((COALESCE(ord.subtotal,0) * 0.029) + 0.30)::numeric, 2)
        ELSE 0
      END AS processor_v,
      -- Service fee: stored, or the residual that reconciles the total.
      CASE
        WHEN ord.platform_service_fee IS NOT NULL THEN ord.platform_service_fee
        ELSE GREATEST(
          COALESCE(ord.total_amount,0)
            - COALESCE(ord.subtotal,0)
            - COALESCE(ord.delivery_fee,0)
            - COALESCE(ord.tax_amount,0)
            - COALESCE(ord.driver_tip,0)
            + GREATEST(COALESCE(ord.discount,0), COALESCE(ord.discount_amount,0)),
          0)
      END AS service_v
    FROM public.orders ord
    LEFT JOIN public.restaurants r ON r.id = ord.restaurant_id
    WHERE ord.status = 'delivered'
      AND COALESCE(ord.delivered_at, ord.ordered_at) >= p_from
      AND COALESCE(ord.delivered_at, ord.ordered_at) <  p_to
  )
  SELECT
    COALESCE(o.delivered_at, o.ordered_at)                         AS order_date,
    COALESCE(o.receipt_number, left(o.id::text, 8))               AS receipt,
    CASE WHEN o.r_store_type IN ('grocery','both') THEN 'grocery' ELSE 'food' END AS order_type,
    COALESCE(o.r_name,'Unknown')                                  AS store_name,
    COALESCE(o.payment_method,'')                                 AS payment_method,
    ROUND(COALESCE(o.subtotal,0)::numeric, 2)                     AS goods_subtotal,
    ROUND(COALESCE(o.delivery_fee,0)::numeric, 2)                 AS delivery_fee,
    ROUND(o.service_v::numeric, 2)                                AS service_fee,
    ROUND(COALESCE(o.tax_amount,0)::numeric, 2)                   AS tax_gct,
    ROUND(COALESCE(o.driver_tip,0)::numeric, 2)                   AS tip,
    ROUND(o.coupon_discount::numeric, 2)                          AS discount,
    ROUND(COALESCE(o.total_amount,0)::numeric, 2)                 AS total_charged,
    ROUND(o.commission_v::numeric, 2)                            AS commission,
    ROUND((COALESCE(o.subtotal,0) - o.commission_v)::numeric, 2)  AS restaurant_payout,
    ROUND(o.driver_pay_v::numeric, 2)                            AS driver_pay,
    ROUND(o.processor_v::numeric, 2)                             AS processor_fee,
    ROUND((COALESCE(o.total_amount,0)
            - (COALESCE(o.subtotal,0) - o.commission_v)
            - o.driver_pay_v
            - o.processor_v
            - COALESCE(o.tax_amount,0))::numeric, 2)             AS platform_profit
  FROM o
  ORDER BY order_date;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.admin_accounting_rows(timestamptz, timestamptz) TO authenticated;

NOTIFY pgrst, 'reload schema';
