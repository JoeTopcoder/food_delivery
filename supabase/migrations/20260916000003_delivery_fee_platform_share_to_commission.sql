-- The platform's share of the delivery fee (the part NOT paid to the driver,
-- i.e. 1 - driver_pay_percent = 20%) counts as commission earnings.
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
  )
  SELECT json_build_object(
    'total_sales',            COALESCE(SUM(total_amount), 0),
    -- Commission = restaurant commission + platform's share of the delivery fee
    'total_commission',       COALESCE(SUM(commission_amount + delivery_fee * (1 - (SELECT driver_pct FROM cfg))), 0),
    'total_delivery_fees',    COALESCE(SUM(delivery_fee), 0),
    'total_driver_tips',      COALESCE(SUM(driver_tip), 0),
    'total_restaurant_payout',COALESCE(SUM(total_amount - commission_amount - delivery_fee), 0),
    'total_driver_payout',    COALESCE(SUM(delivery_fee * (SELECT driver_pct FROM cfg) + COALESCE(driver_tip,0)), 0),
    'order_count',            COUNT(*),
    'monthly_sales',          COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
                                THEN total_amount ELSE 0 END), 0),
    'monthly_commission',     COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
                                THEN commission_amount + delivery_fee * (1 - (SELECT driver_pct FROM cfg)) ELSE 0 END), 0),
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
  FROM public.orders
  WHERE status = 'delivered';
$function$;
NOTIFY pgrst, 'reload schema';
