-- Admin "waive" — reduce what a customer PAYS on an order (e.g. waive J$100 of a
-- J$200 delivery fee so they pay J$100). Audited, admin-gated, over-waive-safe.
--
--  • Unpaid order (payment_status <> 'completed', e.g. cash collected on
--    delivery): reduce orders.total_amount by the waived amount and add it to
--    orders.discount, so the driver collects the reduced total. The platform
--    absorbs the waiver — the driver's pay (derived from delivery_fee) and the
--    restaurant's payout are untouched.
--  • Already-paid order (card/wallet): the customer already paid, so the waiver
--    is given back as a wallet refund via the existing audited admin_refund_order.
CREATE OR REPLACE FUNCTION public.admin_waive_order_amount(
  p_order_id uuid,
  p_amount   numeric,
  p_reason   text,
  p_admin_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_admin   uuid;
  v_user    uuid;
  v_total   numeric;
  v_paid    boolean;
  v_newtot  numeric;
BEGIN
  v_admin := public.require_admin(p_admin_id);   -- same gate as admin_refund_order

  SELECT user_id, total_amount, (payment_status = 'completed')
    INTO v_user, v_total, v_paid
  FROM orders WHERE id = p_order_id;

  IF v_user IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'Waive amount must be positive';
  END IF;
  IF p_amount > COALESCE(v_total, 0) + 0.001 THEN
    RAISE EXCEPTION 'Waive % exceeds order total %', round(p_amount,2), round(v_total,2);
  END IF;

  IF v_paid THEN
    -- Already paid: refund the waived amount to the wallet (audited).
    PERFORM public.admin_refund_order(
      p_order_id, p_amount,
      COALESCE(p_reason, 'Amount waived'), p_admin_id, true);
    v_newtot := v_total;  -- charged total unchanged; money returned via refund
    RETURN jsonb_build_object(
      'waived', true, 'amount', p_amount, 'method', 'wallet_refund',
      'order_total', v_newtot, 'by_admin', v_admin);
  ELSE
    -- Unpaid (cash): the customer simply owes less at delivery.
    v_newtot := round((v_total - p_amount)::numeric, 2);
    UPDATE orders
       SET total_amount = v_newtot,
           discount     = round((COALESCE(discount, 0) + p_amount)::numeric, 2),
           updated_at   = now()
     WHERE id = p_order_id;
    RETURN jsonb_build_object(
      'waived', true, 'amount', p_amount, 'method', 'reduced_total',
      'order_total', v_newtot, 'by_admin', v_admin);
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_waive_order_amount(uuid, numeric, text, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_waive_order_amount(uuid, numeric, text, uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
