-- Make every financial surface recognise the real service fee. Food/grocery
-- orders bake the service fee into total_amount but leave orders.platform_service_fee
-- NULL, so functions that read that column directly undercounted it. The canonical
-- derivation (already used by the admin order-detail UI and admin_accounting_rows)
-- is: stored platform_service_fee when set, else the residual that reconciles the
-- total = total - subtotal - delivery - tax - tip + discount.
--
-- Fixed here:
--   1. get_financial_statistics  — the reported "platform_service_fees_collected"
--      used a fabricated 2.9%+1.30 formula; now uses the real residual. (Net
--      revenue already captured it implicitly via gross = SUM(total_amount).)
--   2. record_platform_revenue   — the platform_revenue_ledger row used the stored
--      (NULL→0) service fee; now uses the residual.
--   3. platform_revenue_ledger   — backfill existing rows' service_fee + total.
-- admin_accounting_rows already uses the residual (unchanged).

-- ── 1. get_financial_statistics ─────────────────────────────────────────────
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
      -- Service fee: stored, else the residual that reconciles the total.
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

-- ── 2. record_platform_revenue ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.record_platform_revenue(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o           orders%ROWTYPE;
  v_driver_pct numeric;
  v_commission numeric;
  v_delivery_share numeric;
  v_hbshare   numeric;
  v_sfee      numeric;
  v_total     numeric;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id;
  END IF;

  SELECT COALESCE(NULLIF(value,'')::numeric, 0.80) INTO v_driver_pct
    FROM app_config WHERE key = 'driver_pay_percent';
  v_driver_pct := COALESCE(v_driver_pct, 0.80);

  v_commission     := COALESCE(o.commission_amount,
                        COALESCE(o.subtotal,0) * COALESCE(o.commission_rate,0))::numeric;
  v_delivery_share := (COALESCE(o.delivery_fee,0) * (1 - v_driver_pct))::numeric;
  v_hbshare        := COALESCE(o.hotbite_savings_share,0)::numeric;
  -- Service fee: stored, else the residual that reconciles the total.
  v_sfee           := CASE
        WHEN o.platform_service_fee IS NOT NULL THEN o.platform_service_fee
        ELSE GREATEST(
          COALESCE(o.total_amount,0)
            - COALESCE(o.subtotal,0)
            - COALESCE(o.delivery_fee,0)
            - COALESCE(o.tax_amount,0)
            - COALESCE(o.driver_tip,0)
            + GREATEST(COALESCE(o.discount,0), COALESCE(o.discount_amount,0)),
          0)
      END::numeric;
  v_total          := ROUND(v_commission + v_delivery_share + v_hbshare + v_sfee, 2);

  INSERT INTO public.platform_revenue_ledger (
    order_id, restaurant_id, restaurant_commission,
    delivery_fee_platform_share, hotbite_savings_share, service_fee, total)
  VALUES (
    p_order_id, o.restaurant_id, ROUND(v_commission,2),
    ROUND(v_delivery_share,2), ROUND(v_hbshare,2), ROUND(v_sfee,2), v_total)
  ON CONFLICT (order_id) DO UPDATE SET
    service_fee = EXCLUDED.service_fee,
    total       = EXCLUDED.total;

  RETURN jsonb_build_object('order_id', p_order_id, 'total', v_total,
                            'hotbite_savings_share', ROUND(v_hbshare,2));
END;
$function$;

-- ── 3. Backfill existing ledger rows ────────────────────────────────────────
UPDATE public.platform_revenue_ledger l
   SET service_fee = v.sfee,
       total = ROUND(l.restaurant_commission + l.delivery_fee_platform_share
                     + l.hotbite_savings_share + v.sfee, 2)
  FROM (
    SELECT o.id,
           ROUND(CASE
             WHEN o.platform_service_fee IS NOT NULL THEN o.platform_service_fee
             ELSE GREATEST(
               COALESCE(o.total_amount,0) - COALESCE(o.subtotal,0)
               - COALESCE(o.delivery_fee,0) - COALESCE(o.tax_amount,0)
               - COALESCE(o.driver_tip,0)
               + GREATEST(COALESCE(o.discount,0), COALESCE(o.discount_amount,0)), 0)
           END::numeric, 2) AS sfee
    FROM orders o
  ) v
 WHERE v.id = l.order_id
   AND l.service_fee IS DISTINCT FROM v.sfee;

NOTIFY pgrst, 'reload schema';
