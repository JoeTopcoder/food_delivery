-- Cash-basis vs accrual (accounting) net revenue + driver-payout liability split.
--
-- Driver pay is EARNED the moment an order is delivered (accrual), but the cash
-- doesn't leave the business until a payout is actually COMPLETED. The dashboard
-- was deducting the full earned driver pay from net revenue even before any
-- driver was paid. This adds clearly-separated figures so nothing is
-- double-counted and liabilities aren't confused with profit:
--
--   earned driver payables      = SUM(delivery_fee × driver_pct + tip) over delivered orders
--                                 (already exposed as total_driver_payout)
--   driver_payouts_completed    = SUM(amount) of settled driver payout_requests
--                                 (status='completed'; a reversal DELETEs the row,
--                                  so this self-corrects). Supports partial payouts.
--   driver_payouts_outstanding  = earned − completed  (what the driver is still owed)
--
--   accounting_net_revenue (accrual) = revenue − restaurant − EARNED driver − Stripe − opex + membership
--   cash_based_net_revenue           = revenue − restaurant − COMPLETED driver − Stripe − opex + membership
--                                    = accounting_net_revenue + driver_payouts_outstanding
--
-- Only COMPLETED payouts reduce the cash-based figure; pending/processing/
-- failed/rejected do not. All arithmetic is exact numeric (no float).
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
    -- Driver payouts that have actually settled (cash left the business).
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
      CASE WHEN ord.platform_service_fee IS NOT NULL THEN ord.platform_service_fee
           ELSE ROUND(((ord.subtotal * 0.029) + 0.30 + 1.00)::numeric, 2) END AS service_fee
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
        - coupon_discount), 0)                                       AS total_commission,
      COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
        THEN total_amount ELSE 0 END), 0)                            AS monthly_sales,
      COALESCE(SUM(CASE WHEN ordered_at >= date_trunc('month', NOW())
        THEN commission_amount + COALESCE(delivery_fee,0) * (1 - (SELECT driver_pct FROM cfg))
          - coupon_discount ELSE 0 END), 0)                          AS monthly_commission
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
    'total_driver_payout',    driver_earned,              -- earned (accrual)
    'driver_payouts_completed', driver_completed,          -- settled (cash paid)
    'driver_payouts_outstanding', driver_outstanding,      -- still owed
    'operating_expenses',     opex,
    'membership_revenue',     membership_revenue,
    'order_count',            order_count,
    'monthly_sales',          monthly_sales,
    'monthly_commission',     monthly_commission,
    'gross_revenue',          gross,
    'stripe_fees_collected',  stripe_fee,
    'platform_service_fees_collected', service_fee,
    -- Accounting (accrual) net: recognises driver expense when EARNED.
    'accounting_net_revenue', gross - restaurant_payout - driver_earned - stripe_fee - opex + membership_revenue,
    -- Cash basis net: deducts only driver pay that has actually settled.
    'cash_based_net_revenue', gross - restaurant_payout - driver_completed - stripe_fee - opex + membership_revenue,
    -- Back-compat: existing readers of net_revenue get the accrual (true) net.
    'net_revenue',            gross - restaurant_payout - driver_earned - stripe_fee - opex + membership_revenue
  )
  FROM calc;
$function$;

NOTIFY pgrst, 'reload schema';
