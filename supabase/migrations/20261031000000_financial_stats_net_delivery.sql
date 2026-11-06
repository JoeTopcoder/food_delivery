-- get_financial_statistics counted the GROSS delivery_fee everywhere, ignoring
-- that a delivery-fee coupon (e.g. FREEDELIVERY) waived what the customer paid.
-- On a free-delivery order this inflated commission + driver payout and drove
-- restaurant payout negative (total_amount - commission - gross delivery_fee).
-- Fix: base every delivery calc on the NET delivery fee actually collected, and
-- compute restaurant payout from subtotal - commission (never total - delivery).

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
      -- Portion of the promo discount that waived the delivery fee.
      GREATEST(
        COALESCE(ord.delivery_fee,0) - CASE
          WHEN ord.promo_code IS NOT NULL AND EXISTS (
            SELECT 1 FROM promo_codes p
            WHERE p.code = ord.promo_code AND p.applies_to = 'delivery_fee')
          THEN LEAST(COALESCE(ord.discount,0), COALESCE(ord.delivery_fee,0))
          ELSE 0 END,
        0) AS net_delivery_fee
    FROM public.orders ord
    WHERE ord.status = 'delivered'
  )
  SELECT json_build_object(
    'total_sales',            COALESCE(SUM(total_amount), 0),
    -- Commission = restaurant commission + platform's share of the NET delivery fee
    'total_commission',       COALESCE(SUM(commission_amount + net_delivery_fee * (1 - (SELECT driver_pct FROM cfg))), 0),
    'total_delivery_fees',    COALESCE(SUM(net_delivery_fee), 0),
    'total_driver_tips',      COALESCE(SUM(driver_tip), 0),
    -- Restaurant earns the food subtotal minus commission (never below 0).
    'total_restaurant_payout',COALESCE(SUM(GREATEST(COALESCE(subtotal,0) - COALESCE(commission_amount,0), 0)), 0),
    -- Driver earns their share of the NET delivery fee + tips.
    'total_driver_payout',    COALESCE(SUM(net_delivery_fee * (SELECT driver_pct FROM cfg) + COALESCE(driver_tip,0)), 0),
    'order_count',            COUNT(*),
    'monthly_sales',          COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
                                THEN total_amount ELSE 0 END), 0),
    'monthly_commission',     COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
                                THEN commission_amount + net_delivery_fee * (1 - (SELECT driver_pct FROM cfg)) ELSE 0 END), 0),
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
