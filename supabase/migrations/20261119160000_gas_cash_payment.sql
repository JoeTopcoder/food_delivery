-- Cooking Gas — Cash on Delivery support.
-- gas_set_cash: customer marks an unpaid order as cash (collected on delivery).
-- The order stays payment_status='unpaid' until it is delivered; the transition
-- to 'delivered' then flips a cash order to 'paid' (cash collected at the door).

CREATE OR REPLACE FUNCTION public.gas_set_cash(p_order uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_customer uuid; v_status text; v_pay text;
BEGIN
  SELECT customer_id, status, payment_status INTO v_customer, v_status, v_pay
    FROM public.gas_orders WHERE id = p_order FOR UPDATE;
  IF v_customer IS NULL THEN RAISE EXCEPTION 'order not found' USING ERRCODE='P0002'; END IF;
  IF v_customer <> auth.uid() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF v_pay = 'paid' THEN RAISE EXCEPTION 'order already paid' USING ERRCODE='P0001'; END IF;
  IF v_status IN ('cancelled','rejected','refunded','completed') THEN
    RAISE EXCEPTION 'order is closed' USING ERRCODE='P0001';
  END IF;
  UPDATE public.gas_orders SET payment_method='cash', updated_at=now() WHERE id=p_order;
  INSERT INTO public.gas_order_events(order_id, prev_status, new_status, actor_role, reason)
    VALUES (p_order, v_status, v_status, 'customer', 'cash on delivery selected');
END;
$$;
REVOKE ALL ON FUNCTION public.gas_set_cash(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gas_set_cash(uuid) TO authenticated;

-- Mark cash orders paid when delivered (cash collected at the door).
CREATE OR REPLACE FUNCTION public.gas_order_transition(
  p_order uuid, p_new text, p_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := public._gas_actor_role(p_order);
  v_cur  text; v_ok boolean; v_method text; v_pay text;
BEGIN
  IF v_role IS NULL THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  SELECT status, payment_method, payment_status INTO v_cur, v_method, v_pay
    FROM public.gas_orders WHERE id = p_order FOR UPDATE;
  IF v_cur IS NULL THEN RAISE EXCEPTION 'order not found' USING ERRCODE = 'P0002'; END IF;

  v_ok := CASE v_cur
    WHEN 'pending_supplier'   THEN p_new IN ('supplier_accepted','rejected','cancelled')
    WHEN 'supplier_accepted'  THEN p_new IN ('preparing','awaiting_payment','cancelled')
    WHEN 'awaiting_payment'   THEN p_new IN ('payment_confirmed','preparing','cancelled')
    WHEN 'payment_confirmed'  THEN p_new IN ('preparing','refund_pending')
    WHEN 'preparing'          THEN p_new IN ('assigned','refund_pending')
    WHEN 'assigned'           THEN p_new IN ('out_for_delivery','refund_pending')
    WHEN 'out_for_delivery'   THEN p_new IN ('delivered','failed_delivery')
    WHEN 'delivered'          THEN p_new IN ('exchange_completed','completed')
    WHEN 'exchange_completed' THEN p_new IN ('completed')
    WHEN 'failed_delivery'    THEN p_new IN ('assigned','refund_pending')
    WHEN 'refund_pending'     THEN p_new IN ('refunded')
    ELSE false
  END;
  IF NOT v_ok THEN RAISE EXCEPTION 'invalid transition % -> %', v_cur, p_new USING ERRCODE = 'P0001'; END IF;

  IF v_role = 'customer' THEN
    IF NOT (p_new = 'cancelled' AND v_cur IN ('pending_supplier','supplier_accepted','awaiting_payment')) THEN
      RAISE EXCEPTION 'not permitted for customer' USING ERRCODE = '42501';
    END IF;
  ELSIF v_role = 'supplier' THEN
    IF p_new IN ('payment_confirmed','refunded') THEN
      RAISE EXCEPTION 'not permitted for supplier' USING ERRCODE = '42501';
    END IF;
  END IF;

  IF p_new IN ('cancelled','rejected') THEN
    PERFORM public._gas_restore_stock(p_order);
    PERFORM public._gas_refund_wallet(p_order);
  ELSIF p_new = 'refunded' THEN
    PERFORM public._gas_refund_wallet(p_order);
  END IF;

  -- Cash on delivery: collect at the door.
  IF p_new = 'delivered' AND v_method = 'cash' AND v_pay = 'unpaid' THEN
    UPDATE public.gas_orders SET payment_status = 'paid' WHERE id = p_order;
  END IF;

  UPDATE public.gas_orders SET
    status = p_new,
    reject_reason = CASE WHEN p_new = 'rejected' THEN p_reason ELSE reject_reason END,
    cancel_reason = CASE WHEN p_new = 'cancelled' THEN p_reason ELSE cancel_reason END,
    accepted_at   = CASE WHEN p_new = 'supplier_accepted' THEN now() ELSE accepted_at END,
    delivered_at  = CASE WHEN p_new = 'delivered' THEN now() ELSE delivered_at END,
    completed_at  = CASE WHEN p_new = 'completed' THEN now() ELSE completed_at END,
    updated_at    = now()
  WHERE id = p_order;

  INSERT INTO public.gas_order_events (order_id, prev_status, new_status, actor_role, reason)
    VALUES (p_order, v_cur, p_new, v_role, p_reason);
END;
$$;
REVOKE ALL ON FUNCTION public.gas_order_transition(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gas_order_transition(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
