-- Migration: per-order margin for the admin dashboard
--
-- Answers "am I making 10-25% on this delivery?" from what the order actually
-- recorded, rather than from a model of what the pricing should have produced.
-- Every figure is a stored column, so this reports reality including any
-- discount, tip or manual adjustment.
--
--   revenue in   = total_amount (what the customer was charged)
--   restaurant   = subtotal - commission_amount
--   driver       = driver_total_pay (tips pass through, excluded below)
--   processor    = stripe_fee_amount
--   platform net = charged - restaurant - driver - processor
--
-- Tips are excluded from both sides: they are collected for the driver and
-- paid to the driver, and leaving them in flatters the margin percentage.

-- Signature changes (new output columns) require a drop first.
DROP FUNCTION IF EXISTS public.admin_order_margins(INT, INT);

CREATE OR REPLACE FUNCTION public.admin_order_margins(
  p_limit INT DEFAULT 100,
  p_days  INT DEFAULT 90
)
RETURNS TABLE (
  order_id        UUID,
  created_at      TIMESTAMPTZ,
  status          TEXT,
  restaurant_name TEXT,
  subtotal        NUMERIC,
  delivery_fee    NUMERIC,
  service_fee     NUMERIC,
  charged         NUMERIC,
  commission      NUMERIC,
  restaurant_paid NUMERIC,
  driver_paid     NUMERIC,
  stripe_fee      NUMERIC,
  tip             NUMERIC,
  net_profit      NUMERIC,
  margin_pct      NUMERIC,
  -- False when the order never recorded what was actually paid out. Such a row
  -- reports a margin far higher than reality (a 67% "profit" is simply an order
  -- with no driver pay and no processor fee written to it), so the UI must
  -- label it rather than average it in.
  data_complete   BOOLEAN,
  missing_fields  TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH base AS (
    SELECT o.id,
           o.created_at,
           o.status,
           r.name AS restaurant_name,
           COALESCE(o.subtotal, 0)              AS subtotal,
           COALESCE(o.delivery_fee, 0)          AS delivery_fee,
           COALESCE(o.platform_service_fee, 0)  AS service_fee,
           COALESCE(o.total_amount, 0)          AS total_amount,
           COALESCE(o.commission_amount,
                    COALESCE(o.subtotal,0) * COALESCE(o.commission_rate, 0.15)) AS commission,
           COALESCE(o.driver_total_pay, 0)      AS driver_pay,
           COALESCE(o.stripe_fee_amount, 0)     AS stripe_fee,
           COALESCE(o.driver_tip, 0) + COALESCE(o.post_delivery_tip, 0) AS tip
    FROM public.orders o
    LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
    WHERE o.created_at > now() - (p_days || ' days')::interval
  ),
  calc AS (
    SELECT b.*,
           -- Tips in and out cancel, so strip them from both sides.
           (b.total_amount - b.tip)                       AS charged_ex_tip,
           (b.subtotal - b.commission)                    AS restaurant_paid,
           GREATEST(b.driver_pay - b.tip, 0)              AS driver_paid_ex_tip
    FROM base b
  )
  -- The money columns are double precision; round() has no (double, int) form,
  -- so every figure is cast before rounding.
  SELECT c.id, c.created_at, c.status, c.restaurant_name,
         ROUND(c.subtotal::numeric, 2), ROUND(c.delivery_fee::numeric, 2),
         ROUND(c.service_fee::numeric, 2), ROUND(c.charged_ex_tip::numeric, 2),
         ROUND(c.commission::numeric, 2), ROUND(c.restaurant_paid::numeric, 2),
         ROUND(c.driver_paid_ex_tip::numeric, 2), ROUND(c.stripe_fee::numeric, 2),
         ROUND(c.tip::numeric, 2),
         ROUND((c.charged_ex_tip - c.restaurant_paid - c.driver_paid_ex_tip - c.stripe_fee)::numeric, 2),
         CASE WHEN c.charged_ex_tip > 0
              THEN ROUND((((c.charged_ex_tip - c.restaurant_paid - c.driver_paid_ex_tip - c.stripe_fee)
                          / c.charged_ex_tip) * 100)::numeric, 1)
              ELSE NULL END,
         (c.driver_pay > 0 AND c.stripe_fee > 0 AND c.commission > 0),
         NULLIF(CONCAT_WS(', ',
           CASE WHEN c.driver_pay  <= 0 THEN 'driver pay'    END,
           CASE WHEN c.stripe_fee  <= 0 THEN 'processor fee' END,
           CASE WHEN c.commission  <= 0 THEN 'commission'    END
         ), '')
  FROM calc c
  ORDER BY c.created_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.admin_order_margins TO authenticated;

NOTIFY pgrst, 'reload schema';
