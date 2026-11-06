-- Financials, corrected economics for coupons of ANY kind:
--  • The DRIVER is always paid their full share of the GROSS delivery fee — a
--    customer's free-delivery (or any) coupon never reduces driver pay; the
--    platform absorbs the promo.
--  • The RESTAURANT is always paid the food subtotal minus commission.
--  • The PLATFORM absorbs the ENTIRE coupon discount (we can give a coupon for
--    anything — delivery, food, whole order), so the full discount is deducted
--    from the platform's commission/margin.
--
-- Derivation (per order): platform margin
--   = restaurant_commission + platform_delivery_share − total_discount
--   = commission_amount + delivery_fee*(1−driver_pct) − discount
-- (driver takes delivery_fee*driver_pct; discount is whatever the coupon waived).

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
  o AS (
    SELECT
      ord.*,
      -- Total coupon discount on the order (any target). Some orders populate
      -- `discount`, some `discount_amount`; take whichever is larger.
      GREATEST(COALESCE(ord.discount,0), COALESCE(ord.discount_amount,0)) AS coupon_discount
    FROM public.orders ord
    WHERE ord.status = 'delivered'
  )
  SELECT json_build_object(
    'total_sales',            COALESCE(SUM(total_amount), 0),
    -- Platform margin = restaurant commission + platform's share of the GROSS
    -- delivery fee, LESS the coupon discount the platform gave away.
    'total_commission',       COALESCE(SUM(
                                commission_amount
                                + COALESCE(delivery_fee,0) * (1 - (SELECT driver_pct FROM cfg))
                                - coupon_discount), 0),
    'total_discounts',        COALESCE(SUM(coupon_discount), 0),
    'total_delivery_fees',    COALESCE(SUM(delivery_fee), 0),
    'total_driver_tips',      COALESCE(SUM(driver_tip), 0),
    -- Restaurant earns the food subtotal minus commission (never below 0).
    'total_restaurant_payout',COALESCE(SUM(GREATEST(COALESCE(subtotal,0) - COALESCE(commission_amount,0), 0)), 0),
    -- Driver ALWAYS earns their share of the GROSS delivery fee + tips.
    'total_driver_payout',    COALESCE(SUM(COALESCE(delivery_fee,0) * (SELECT driver_pct FROM cfg) + COALESCE(driver_tip,0)), 0),
    'order_count',            COUNT(*),
    'monthly_sales',          COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
                                THEN total_amount ELSE 0 END), 0),
    'monthly_commission',     COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
                                THEN commission_amount
                                   + COALESCE(delivery_fee,0) * (1 - (SELECT driver_pct FROM cfg))
                                   - coupon_discount ELSE 0 END), 0),
    'gross_revenue',          COALESCE(SUM(total_amount), 0),
    'stripe_fees_collected',  COALESCE(SUM(
                                CASE WHEN stripe_fee_amount IS NOT NULL THEN stripe_fee_amount
                                  ELSE ROUND(((subtotal * 0.029) + 0.30)::numeric, 2) END), 0),
    'platform_service_fees_collected', COALESCE(SUM(
                                CASE WHEN platform_service_fee IS NOT NULL THEN platform_service_fee
                                  ELSE ROUND(((subtotal * 0.029) + 0.30 + 1.00)::numeric, 2) END), 0),
    'net_revenue',            COALESCE(SUM(total_amount) - SUM(
                                CASE WHEN stripe_fee_amount IS NOT NULL THEN stripe_fee_amount
                                  ELSE ROUND(((subtotal * 0.029) + 0.30)::numeric, 2) END), 0)
  )
  FROM o;
$function$;

NOTIFY pgrst, 'reload schema';
