-- Admin removes/reduces an order item (restaurant is out of it). Recomputes the
-- order subtotal + total so the customer's total updates. If the order was
-- already PAID (card/wallet), the removed amount is credited back to the
-- customer's wallet via the audited admin_refund_order. For an UNPAID (cash)
-- order, lowering the total is enough — the driver simply collects less.
CREATE OR REPLACE FUNCTION public.admin_edit_order_item(
  p_item_id uuid, p_qty integer, p_admin_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_admin uuid; v_order uuid; v_price numeric;
  v_old_line numeric; v_new_line numeric; v_delta numeric;
  v_new_sub numeric; v_old_total numeric; v_new_total numeric;
  v_paid boolean; v_refunded numeric := 0;
BEGIN
  v_admin := public.require_admin(p_admin_id);

  SELECT order_id, price, COALESCE(subtotal, price * quantity)
    INTO v_order, v_price, v_old_line
  FROM order_items WHERE id = p_item_id;
  IF v_order IS NULL THEN RAISE EXCEPTION 'Order item not found'; END IF;

  SELECT total_amount, (payment_status = 'completed')
    INTO v_old_total, v_paid
  FROM orders WHERE id = v_order;

  -- Remove (qty 0) or re-quantify the line.
  IF p_qty <= 0 THEN
    DELETE FROM order_items WHERE id = p_item_id;
    v_new_line := 0;
  ELSE
    v_new_line := round((v_price * p_qty)::numeric, 2);
    UPDATE order_items SET quantity = p_qty, subtotal = v_new_line WHERE id = p_item_id;
  END IF;

  v_delta := round((v_old_line - v_new_line)::numeric, 2);          -- + = reduction
  SELECT round(COALESCE(sum(subtotal), 0)::numeric, 2) INTO v_new_sub
    FROM order_items WHERE order_id = v_order;
  v_new_total := round((COALESCE(v_old_total, 0) - v_delta)::numeric, 2);
  IF v_new_total < 0 THEN v_new_total := 0; END IF;

  -- Already paid (card/wallet): refund the removed amount to the wallet BEFORE
  -- lowering the recorded total (so the refund is checked against what was paid).
  IF v_paid AND v_delta > 0 THEN
    PERFORM public.admin_refund_order(
      v_order, v_delta, 'Item removed/adjusted by admin', p_admin_id, true);
    v_refunded := v_delta;
  END IF;

  UPDATE orders
     SET subtotal = v_new_sub, total_amount = v_new_total, updated_at = now()
   WHERE id = v_order;

  RETURN jsonb_build_object(
    'ok', true, 'order_id', v_order, 'subtotal', v_new_sub, 'total', v_new_total,
    'reduced', v_delta, 'refunded', v_refunded, 'paid', v_paid);
END; $fn$;

NOTIFY pgrst, 'reload schema';
