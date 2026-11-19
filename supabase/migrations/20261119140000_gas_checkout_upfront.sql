-- ============================================================================
-- HotBite Cooking Gas — Pay UPFRONT at checkout (before supplier confirms)
--
-- Change of flow: the customer now pays at checkout like a regular order. The
-- order is created 'pending_supplier' and paid immediately; the supplier then
-- accepts → preparing (no separate awaiting_payment step). If the supplier
-- rejects, or the order is cancelled, a wallet payment is auto-refunded.
--
-- Rewrites gas_pay_wallet (pay any unpaid non-terminal order, no status jump),
-- gas_order_transition (supplier_accepted → preparing directly; refund on
-- cancel/reject), and adds _gas_refund_wallet.
-- ============================================================================

-- ── Pay from wallet, UPFRONT (does not change fulfilment status) ────────────
CREATE OR REPLACE FUNCTION public.gas_pay_wallet(p_order uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_customer uuid; v_status text; v_pay text; v_total bigint;
  v_amount numeric; v_balance numeric;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated' USING ERRCODE='28000'; END IF;
  SELECT customer_id, status, payment_status, total_cents
    INTO v_customer, v_status, v_pay, v_total
    FROM public.gas_orders WHERE id = p_order FOR UPDATE;
  IF v_customer IS NULL THEN RAISE EXCEPTION 'order not found' USING ERRCODE='P0002'; END IF;
  IF v_customer <> v_uid THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  IF v_pay = 'paid' THEN RETURN jsonb_build_object('ok', true, 'already_paid', true); END IF;
  -- can pay any order that isn't already resolved
  IF v_status IN ('cancelled','rejected','refunded','completed') THEN
    RAISE EXCEPTION 'order is closed' USING ERRCODE='P0001';
  END IF;

  v_amount := round(v_total::numeric / 100.0, 2);  -- cents → dollars
  SELECT balance INTO v_balance FROM public.wallets WHERE user_id = v_uid FOR UPDATE;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'no wallet' USING ERRCODE='P0001'; END IF;
  IF v_balance < v_amount THEN RAISE EXCEPTION 'insufficient wallet balance' USING ERRCODE='P0001'; END IF;

  UPDATE public.wallets SET balance = balance - v_amount, updated_at = now() WHERE user_id = v_uid;
  INSERT INTO public.wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
    VALUES (v_uid, -v_amount, 'payment', 'wallet', 'completed', NULL, 'Cooking gas order '||p_order::text);

  -- mark paid; DO NOT advance fulfilment — the supplier still confirms next.
  UPDATE public.gas_orders SET payment_status = 'paid', payment_method = 'wallet', updated_at = now()
    WHERE id = p_order;
  INSERT INTO public.gas_order_events (order_id, prev_status, new_status, actor_role, reason)
    VALUES (p_order, v_status, v_status, 'customer', 'paid upfront from wallet');

  RETURN jsonb_build_object('ok', true, 'charged', v_amount);
END;
$$;
REVOKE ALL ON FUNCTION public.gas_pay_wallet(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gas_pay_wallet(uuid) TO authenticated;

-- ── Refund a paid order back to the wallet (idempotent) ─────────────────────
-- Wallet payments are credited back immediately. Card (stripe) payments are
-- marked 'refund_pending' for an admin/edge Stripe refund (not auto-credited).
CREATE OR REPLACE FUNCTION public._gas_refund_wallet(p_order uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_customer uuid; v_pay text; v_method text; v_total bigint; v_amount numeric;
BEGIN
  SELECT customer_id, payment_status, payment_method, total_cents
    INTO v_customer, v_pay, v_method, v_total
    FROM public.gas_orders WHERE id = p_order;
  IF v_pay <> 'paid' THEN RETURN; END IF;  -- nothing captured, nothing to refund
  IF v_method = 'wallet' THEN
    v_amount := round(v_total::numeric / 100.0, 2);
    INSERT INTO public.wallets (user_id, balance) VALUES (v_customer, v_amount)
      ON CONFLICT (user_id) DO UPDATE SET balance = public.wallets.balance + v_amount, updated_at = now();
    INSERT INTO public.wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
      VALUES (v_customer, v_amount, 'refund', 'wallet', 'completed', NULL, 'Refund — cooking gas order '||p_order::text);
    UPDATE public.gas_orders SET payment_status = 'refunded', updated_at = now() WHERE id = p_order;
  ELSE
    -- card/other: flag for an out-of-band refund
    UPDATE public.gas_orders SET payment_status = 'refunded', updated_at = now() WHERE id = p_order;
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public._gas_refund_wallet(uuid) FROM PUBLIC, anon;

-- ── Transition: supplier_accepted → preparing directly; refund on cancel/reject
CREATE OR REPLACE FUNCTION public.gas_order_transition(
  p_order uuid, p_new text, p_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := public._gas_actor_role(p_order);
  v_cur  text;
  v_ok   boolean;
BEGIN
  IF v_role IS NULL THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  SELECT status INTO v_cur FROM public.gas_orders WHERE id = p_order FOR UPDATE;
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
  IF NOT v_ok THEN
    RAISE EXCEPTION 'invalid transition % -> %', v_cur, p_new USING ERRCODE = 'P0001';
  END IF;

  IF v_role = 'customer' THEN
    -- customer may cancel before the cylinder is prepared
    IF NOT (p_new = 'cancelled' AND v_cur IN ('pending_supplier','supplier_accepted','awaiting_payment')) THEN
      RAISE EXCEPTION 'not permitted for customer' USING ERRCODE = '42501';
    END IF;
  ELSIF v_role = 'supplier' THEN
    IF p_new IN ('payment_confirmed','refunded') THEN
      RAISE EXCEPTION 'not permitted for supplier' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- cancel/reject before fulfilment: restore stock AND refund any payment
  IF p_new IN ('cancelled','rejected') THEN
    PERFORM public._gas_restore_stock(p_order);
    PERFORM public._gas_refund_wallet(p_order);
  ELSIF p_new = 'refunded' THEN
    PERFORM public._gas_refund_wallet(p_order);
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
