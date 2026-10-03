-- Shared Member Savings — admin reporting.
-- Two admin-gated read RPCs over a [p_from, p_to) window on orders.created_at:
--   * admin_member_savings_summary  → one row of platform-wide totals
--   * admin_member_savings_by_store → per-restaurant breakdown
-- A "member order" here is any order that actually applied the shared model
-- (hotbite_savings_share > 0 OR member_savings > 0). All money is in currency
-- units (numeric), rounded to 2, so the admin UI shows it directly.
--
-- NOTE: the orders money columns are double precision, so every sum is cast to
-- numeric before round() (round(double precision,int) does not exist).
--
-- Refunds: figures are reported NET of refunds. We do NOT reverse the HotBite
-- savings share in the ledger (the system reverses no post-delivery earnings);
-- instead the report subtracts refunds recorded against these orders from the
-- net contribution, which is the correct place for that attribution.
--
-- Reconciliation note: commission is recorded at place-order on the CUSTOMER
-- subtotal (member price), while the store is actually paid on
-- subtotal - hotbite_savings_share. The report therefore reports
-- store_payout_base = subtotal - hotbite_savings_share separately from
-- commission so the two are never conflated.

CREATE OR REPLACE FUNCTION public.admin_member_savings_summary(
  p_from timestamptz,
  p_to   timestamptz
)
RETURNS TABLE (
  member_orders       bigint,
  gross_member_sales  numeric,
  customer_savings    numeric,
  hotbite_share_rev   numeric,
  store_payout_base   numeric,
  commission_total    numeric,
  delivery_fees       numeric,
  service_fees        numeric,
  refunds_total       numeric,
  net_contribution    numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN QUERY
  WITH mem AS (
    SELECT o.id, o.restaurant_id,
           COALESCE(o.subtotal,0)::numeric              AS subtotal,
           COALESCE(o.member_savings,0)::numeric        AS csave,
           COALESCE(o.hotbite_savings_share,0)::numeric AS hbshare,
           COALESCE(o.commission_amount,
                    COALESCE(o.subtotal,0)*COALESCE(o.commission_rate,0))::numeric AS commission,
           COALESCE(o.delivery_fee,0)::numeric          AS dfee,
           COALESCE(o.platform_service_fee,0)::numeric  AS sfee
    FROM orders o
    WHERE o.created_at >= p_from AND o.created_at < p_to
      AND (COALESCE(o.hotbite_savings_share,0) > 0 OR COALESCE(o.member_savings,0) > 0)
  ),
  ref AS (
    SELECT COALESCE(sum(r.amount),0)::numeric AS refunded
    FROM refunds r
    WHERE r.status IN ('approved','processed')
      AND r.order_id IN (SELECT id FROM mem)
  )
  SELECT
    (SELECT count(*) FROM mem),
    ROUND(COALESCE((SELECT sum(subtotal) FROM mem),0),2),
    ROUND(COALESCE((SELECT sum(csave) FROM mem),0),2),
    ROUND(COALESCE((SELECT sum(hbshare) FROM mem),0),2),
    ROUND(COALESCE((SELECT sum(subtotal - hbshare) FROM mem),0),2),
    ROUND(COALESCE((SELECT sum(commission) FROM mem),0),2),
    ROUND(COALESCE((SELECT sum(dfee) FROM mem),0),2),
    ROUND(COALESCE((SELECT sum(sfee) FROM mem),0),2),
    ROUND((SELECT refunded FROM ref),2),
    ROUND(
      COALESCE((SELECT sum(hbshare) FROM mem),0)
      + COALESCE((SELECT sum(commission) FROM mem),0)
      + COALESCE((SELECT sum(sfee) FROM mem),0)
      - (SELECT refunded FROM ref), 2);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_member_savings_by_store(
  p_from timestamptz,
  p_to   timestamptz
)
RETURNS TABLE (
  restaurant_id      uuid,
  restaurant_name    text,
  member_orders      bigint,
  gross_member_sales numeric,
  customer_savings   numeric,
  hotbite_share_rev  numeric,
  store_payout_base  numeric,
  refunds_total      numeric
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN QUERY
  WITH mem AS (
    SELECT o.id, o.restaurant_id,
           COALESCE(o.subtotal,0)::numeric              AS subtotal,
           COALESCE(o.member_savings,0)::numeric        AS csave,
           COALESCE(o.hotbite_savings_share,0)::numeric AS hbshare
    FROM orders o
    WHERE o.created_at >= p_from AND o.created_at < p_to
      AND (COALESCE(o.hotbite_savings_share,0) > 0 OR COALESCE(o.member_savings,0) > 0)
  ),
  ref AS (
    SELECT m.restaurant_id, COALESCE(sum(r.amount),0)::numeric AS refunded
    FROM refunds r JOIN mem m ON m.id = r.order_id
    WHERE r.status IN ('approved','processed')
    GROUP BY m.restaurant_id
  )
  SELECT m.restaurant_id,
         r.name,
         count(*)::bigint,
         ROUND(sum(m.subtotal),2),
         ROUND(sum(m.csave),2),
         ROUND(sum(m.hbshare),2),
         ROUND(sum(m.subtotal - m.hbshare),2),
         ROUND(COALESCE(rf.refunded,0),2)
  FROM mem m
  LEFT JOIN restaurants r ON r.id = m.restaurant_id
  LEFT JOIN ref rf ON rf.restaurant_id = m.restaurant_id
  GROUP BY m.restaurant_id, r.name, rf.refunded
  ORDER BY ROUND(sum(m.hbshare),2) DESC;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_member_savings_summary(timestamptz,timestamptz) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_member_savings_by_store(timestamptz,timestamptz) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_member_savings_summary(timestamptz,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_member_savings_by_store(timestamptz,timestamptz) TO authenticated;

NOTIFY pgrst, 'reload schema';
