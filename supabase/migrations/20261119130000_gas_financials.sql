-- ============================================================================
-- HotBite Cooking Gas — Financial rollup (admin reporting)
--
-- get_gas_financials(from, to): aggregates PAID gas orders in a date range into
-- auditable buckets that keep gas distinguishable from food/grocery while rolling
-- up to company reporting. All amounts JMD cents.
--
-- Accounting discipline (matches the brief):
--   • Cylinder DEPOSITS are a refundable LIABILITY, never platform revenue.
--   • Operator/supplier payouts are LIABILITIES until paid — NOT profit just
--     because the cash sits in HotBite's account.
--   • Platform revenue = service fees + supplier commission (NOT gross).
-- ============================================================================
CREATE OR REPLACE FUNCTION public.get_gas_financials(
  p_from date DEFAULT (now() AT TIME ZONE 'America/Jamaica')::date - 30,
  p_to   date DEFAULT (now() AT TIME ZONE 'America/Jamaica')::date
) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH paid AS (
    SELECT o.*, s.commission_bps
    FROM public.gas_orders o
    JOIN public.gas_suppliers s ON s.id = o.supplier_id
    WHERE o.payment_status = 'paid'
      AND (o.completed_at IS NULL OR o.status <> 'refunded')
      AND (o.placed_at AT TIME ZONE 'America/Jamaica')::date BETWEEN p_from AND p_to
  ),
  agg AS (
    SELECT
      count(*)                                            AS orders,
      COALESCE(sum(items_cents), 0)                       AS gmv_items_cents,
      COALESCE(sum(deposit_cents), 0)                     AS deposits_liability_cents,
      COALESCE(sum(delivery_cents), 0)                    AS delivery_cents,
      COALESCE(sum(service_fee_cents), 0)                 AS service_fee_cents,
      COALESCE(sum(discount_cents), 0)                    AS discount_cents,
      COALESCE(sum(total_cents), 0)                       AS cash_collected_cents,
      -- supplier commission = items * bps/10000 (platform's cut of merchandise)
      COALESCE(sum((items_cents * commission_bps) / 10000), 0) AS commission_cents
    FROM paid
  ),
  payouts AS (
    SELECT COALESCE(sum(a.payout_cents), 0) AS operator_liability_cents
    FROM public.gas_delivery_assignments a
    JOIN paid p ON p.id = a.order_id
    WHERE a.status <> 'unassigned'
  )
  SELECT jsonb_build_object(
    'from', p_from, 'to', p_to, 'currency', 'JMD',
    'orders', agg.orders,
    'gmv_items_cents', agg.gmv_items_cents,
    'deposits_liability_cents', agg.deposits_liability_cents,       -- owed back to customers
    'delivery_cents', agg.delivery_cents,
    'service_fee_cents', agg.service_fee_cents,
    'discount_cents', agg.discount_cents,
    'cash_collected_cents', agg.cash_collected_cents,               -- what customers paid in total
    'commission_cents', agg.commission_cents,                      -- platform cut of merchandise
    'supplier_liability_cents', (agg.gmv_items_cents - agg.commission_cents), -- owed to suppliers
    'operator_payout_liability_cents', payouts.operator_liability_cents,     -- owed to delivery ops
    -- platform revenue recognised = service fees + commission (NOT deposits, NOT gross)
    'platform_revenue_cents', (agg.service_fee_cents + agg.commission_cents + agg.delivery_cents
                               - payouts.operator_liability_cents)
  )
  FROM agg, payouts;
$$;
REVOKE ALL ON FUNCTION public.get_gas_financials(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_gas_financials(date, date) TO authenticated;

-- Admin-only guard wrapper note: the RPC itself is SECURITY DEFINER and reads
-- across all suppliers, so it is gated at call sites to admins. Enforce here too:
CREATE OR REPLACE FUNCTION public.get_gas_financials_admin(
  p_from date DEFAULT (now() AT TIME ZONE 'America/Jamaica')::date - 30,
  p_to   date DEFAULT (now() AT TIME ZONE 'America/Jamaica')::date
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'admin only' USING ERRCODE = '42501'; END IF;
  RETURN public.get_gas_financials(p_from, p_to);
END;
$$;
REVOKE ALL ON FUNCTION public.get_gas_financials_admin(date, date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_gas_financials_admin(date, date) TO authenticated;

NOTIFY pgrst, 'reload schema';
