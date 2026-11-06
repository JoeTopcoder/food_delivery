-- Net Revenue must be TRUE net: gross revenue minus every payout and cost that
-- HotBite Delivery incurs — restaurant payouts, driver payouts, Stripe fees, and
-- any other operating expenses — not just Stripe. Coupon discounts are already
-- reflected in gross revenue (customers paid the discounted total) and the
-- payouts below are on the gross amounts, so the discount is captured once, not
-- double-subtracted. Service fees and commission are platform income that lives
-- inside gross, so they are not added again.

CREATE OR REPLACE FUNCTION public.get_financial_statistics()
 RETURNS json
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH cfg AS (
    SELECT COALESCE(
      (SELECT NULLIF(value,'')::numeric FROM app_config WHERE key='driver_pay_percent'),
      0.80) AS driver_pct
  ),
  oe AS (
    -- Other operating expenses. No expenses table exists yet, so this is 0;
    -- wire a real source here later and the net below picks it up automatically.
    SELECT 0::numeric AS operating_expenses
  ),
  o AS (
    SELECT
      ord.*,
      GREATEST(COALESCE(ord.discount,0), COALESCE(ord.discount_amount,0)) AS coupon_discount,
      GREATEST(COALESCE(ord.subtotal,0) - COALESCE(ord.commission_amount,0), 0) AS restaurant_payout,
      COALESCE(ord.delivery_fee,0) * (SELECT driver_pct FROM cfg) + COALESCE(ord.driver_tip,0) AS driver_payout,
      CASE WHEN ord.stripe_fee_amount IS NOT NULL THEN ord.stripe_fee_amount
           ELSE ROUND(((ord.subtotal * 0.029) + 0.30)::numeric, 2) END AS stripe_fee,
      CASE WHEN ord.platform_service_fee IS NOT NULL THEN ord.platform_service_fee
           ELSE ROUND(((ord.subtotal * 0.029) + 0.30 + 1.00)::numeric, 2) END AS service_fee
    FROM public.orders ord
    WHERE ord.status = 'delivered'
  )
  SELECT json_build_object(
    'total_sales',            COALESCE(SUM(total_amount), 0),
    'total_commission',       COALESCE(SUM(
                                commission_amount
                                + COALESCE(delivery_fee,0) * (1 - (SELECT driver_pct FROM cfg))
                                - coupon_discount), 0),
    'total_discounts',        COALESCE(SUM(coupon_discount), 0),
    'total_delivery_fees',    COALESCE(SUM(delivery_fee), 0),
    'total_driver_tips',      COALESCE(SUM(driver_tip), 0),
    'total_restaurant_payout',COALESCE(SUM(restaurant_payout), 0),
    'total_driver_payout',    COALESCE(SUM(driver_payout), 0),
    'operating_expenses',     (SELECT operating_expenses FROM oe),
    'order_count',            COUNT(*),
    'monthly_sales',          COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
                                THEN total_amount ELSE 0 END), 0),
    'monthly_commission',     COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
                                THEN commission_amount
                                   + COALESCE(delivery_fee,0) * (1 - (SELECT driver_pct FROM cfg))
                                   - coupon_discount ELSE 0 END), 0),
    'gross_revenue',          COALESCE(SUM(total_amount), 0),
    'stripe_fees_collected',  COALESCE(SUM(stripe_fee), 0),
    'platform_service_fees_collected', COALESCE(SUM(service_fee), 0),
    -- TRUE net = gross − restaurant payouts − driver payouts − Stripe − other opex.
    'net_revenue',            COALESCE(SUM(total_amount)
                                - SUM(restaurant_payout)
                                - SUM(driver_payout)
                                - SUM(stripe_fee), 0)
                              - (SELECT operating_expenses FROM oe)
  )
  FROM o;
$function$;

NOTIFY pgrst, 'reload schema';
