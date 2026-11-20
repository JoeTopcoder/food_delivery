-- Include the platform service fee in "Commission Earnings". Previously
-- total_commission = restaurant commission + delivery platform share - discounts.
-- Now it also adds the service fee (which was only reported separately as
-- platform_service_fees_collected). Only the two commission sums change.
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
  oe AS (SELECT 0::numeric AS operating_expenses),
  mem AS (
    SELECT COALESCE(SUM(price_paid), 0)::numeric AS membership_revenue
    FROM customer_memberships WHERE status = 'active'
  ),
  paid AS (
    SELECT COALESCE(SUM(amount), 0)::numeric AS driver_completed
    FROM payout_requests
    WHERE requester_type = 'driver' AND status = 'completed'
  ),
  o AS (
    SELECT
      ord.*,
      GREATEST(COALESCE(ord.discount,0), COALESCE(ord.discount_amount,0)) AS coupon_discount,
      GREATEST(COALESCE(ord.subtotal,0) - COALESCE(ord.commission_amount,0), 0) AS restaurant_payout,
      COALESCE(ord.delivery_fee,0) * (SELECT driver_pct FROM cfg) + COALESCE(ord.driver_tip,0) AS driver_payout,
      CASE
        WHEN lower(COALESCE(ord.payment_method,'')) IN ('cash','cash_on_delivery','cod') THEN 0
        WHEN ord.stripe_fee_amount IS NOT NULL THEN ord.stripe_fee_amount
        WHEN lower(COALESCE(ord.payment_method,'')) IN ('stripe','card','credit_card','debit_card')
          THEN ROUND(((ord.subtotal * 0.029) + 0.30)::numeric, 2)
        ELSE 0
      END AS stripe_fee,
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
      END AS service_fee
    FROM public.orders ord
    WHERE ord.status = 'delivered'
  ),
  agg AS (
    SELECT
      COALESCE(SUM(total_amount),0)                                   AS gross,
      COALESCE(SUM(restaurant_payout),0)                              AS restaurant_payout,
      COALESCE(SUM(driver_payout),0)                                  AS driver_earned,
      COALESCE(SUM(stripe_fee),0)                                     AS stripe_fee,
      COALESCE(SUM(service_fee),0)                                    AS service_fee,
      COALESCE(SUM(coupon_discount),0)                                AS coupon_discount,
      COALESCE(SUM(delivery_fee),0)                                   AS delivery_fees,
      COALESCE(SUM(driver_tip),0)                                     AS driver_tips,
      COUNT(*)                                                        AS order_count,
      COALESCE(SUM(commission_amount
        + COALESCE(delivery_fee,0) * (1 - (SELECT driver_pct FROM cfg))
        - coupon_discount + service_fee), 0)                         AS total_commission,
      COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
        THEN total_amount ELSE 0 END), 0)                            AS monthly_sales,
      COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
        THEN commission_amount + COALESCE(delivery_fee,0) * (1 - (SELECT driver_pct FROM cfg))
          - coupon_discount + service_fee ELSE 0 END), 0)            AS monthly_commission
    FROM o
  ),
  calc AS (
    SELECT a.*,
      (SELECT operating_expenses FROM oe) AS opex,
      (SELECT membership_revenue FROM mem) AS membership_revenue,
      (SELECT driver_completed FROM paid) AS driver_completed,
      GREATEST(a.driver_earned - (SELECT driver_completed FROM paid), 0) AS driver_outstanding
    FROM agg a
  )
  SELECT json_build_object(
    'total_sales',            gross + membership_revenue,
    'total_commission',       total_commission,
    'total_discounts',        coupon_discount,
    'total_delivery_fees',    delivery_fees,
    'total_driver_tips',      driver_tips,
    'total_restaurant_payout',restaurant_payout,
    'total_driver_payout',    driver_earned,
    'driver_payouts_completed', driver_completed,
    'driver_payouts_outstanding', driver_outstanding,
    'operating_expenses',     opex,
    'membership_revenue',     membership_revenue,
    'order_count',            order_count,
    'monthly_sales',          monthly_sales,
    'monthly_commission',     monthly_commission,
    'gross_revenue',          gross,
    'stripe_fees_collected',  stripe_fee,
    'platform_service_fees_collected', service_fee,
    'accounting_net_revenue', gross - restaurant_payout - driver_earned - stripe_fee - opex + membership_revenue,
    'cash_based_net_revenue', gross - restaurant_payout - driver_completed - stripe_fee - opex + membership_revenue,
    'net_revenue',            gross - restaurant_payout - driver_earned - stripe_fee - opex + membership_revenue
  )
  FROM calc;
$function$;

NOTIFY pgrst, 'reload schema';
