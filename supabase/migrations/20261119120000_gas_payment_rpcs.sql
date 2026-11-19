-- ============================================================================
-- HotBite Cooking Gas — Payment RPCs
--
-- Payment happens AFTER the supplier accepts (order reaches 'awaiting_payment').
--   • gas_pay_wallet     — customer pays from their HotBite wallet (audited
--                          ledger row, debit negative in DOLLARS). Authenticated.
--   • gas_confirm_payment— trusted server callback (Stripe/NCB webhook via the
--                          gas-pay-order edge fn). service_role ONLY. Idempotent.
--
-- Money note: gas_orders money is JMD CENTS (bigint); wallet_transactions/wallets
-- are DOLLARS (numeric). Convert cents/100.0. wallet_transactions.order_id FKs to
-- `orders`, so gas payments leave it NULL and name the gas order in description.
-- Deposits are included in the charged total but remain a refundable liability.
-- ============================================================================

-- ── Trusted confirm (service_role only; used by the payment edge fn/webhooks) ─
-- Idempotent: a second call for an already-paid order is a no-op. Does the state
-- change inline (NOT via gas_order_transition, which role-gates money states).
CREATE OR REPLACE FUNCTION public.gas_confirm_payment(
  p_order uuid, p_method text, p_ref text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_status text; v_pay text;
BEGIN
  SELECT status, payment_status INTO v_status, v_pay
    FROM public.gas_orders WHERE id = p_order FOR UPDATE;
  IF v_status IS NULL THEN RAISE EXCEPTION 'order not found' USING ERRCODE = 'P0002'; END IF;
  IF v_pay = 'paid' THEN RETURN; END IF;  -- idempotent
  IF v_status <> 'awaiting_payment' THEN
    RAISE EXCEPTION 'order is not awaiting payment (status %)', v_status USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.gas_orders SET
    payment_status = 'paid', payment_method = COALESCE(p_method, payment_method),
    payment_ref = COALESCE(p_ref, payment_ref), status = 'payment_confirmed', updated_at = now()
  WHERE id = p_order;

  INSERT INTO public.gas_order_events (order_id, prev_status, new_status, actor_role, reason)
    VALUES (p_order, 'awaiting_payment', 'payment_confirmed', 'system', 'payment confirmed: '||COALESCE(p_method,'?'));
END;
$$;
REVOKE ALL ON FUNCTION public.gas_confirm_payment(uuid, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.gas_confirm_payment(uuid, text, text) TO service_role;

-- ── Customer pays from wallet (authenticated) ───────────────────────────────
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
  IF v_status <> 'awaiting_payment' THEN
    RAISE EXCEPTION 'order is not awaiting payment' USING ERRCODE='P0001';
  END IF;

  v_amount := round(v_total::numeric / 100.0, 2);  -- cents → dollars

  -- lock + check wallet balance (wallets.balance is authoritative)
  SELECT balance INTO v_balance FROM public.wallets WHERE user_id = v_uid FOR UPDATE;
  IF v_balance IS NULL THEN RAISE EXCEPTION 'no wallet' USING ERRCODE='P0001'; END IF;
  IF v_balance < v_amount THEN
    RAISE EXCEPTION 'insufficient wallet balance' USING ERRCODE='P0001';
  END IF;

  -- debit (negative, type 'payment'); order_id NULL (FK is to orders), gas id in description
  UPDATE public.wallets SET balance = balance - v_amount, updated_at = now() WHERE user_id = v_uid;
  INSERT INTO public.wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
    VALUES (v_uid, -v_amount, 'payment', 'wallet', 'completed', NULL, 'Cooking gas order '||p_order::text);

  -- confirm payment + advance state (inline; this is trusted definer code)
  UPDATE public.gas_orders SET
    payment_status = 'paid', payment_method = 'wallet', status = 'payment_confirmed', updated_at = now()
  WHERE id = p_order;
  INSERT INTO public.gas_order_events (order_id, prev_status, new_status, actor_role, reason)
    VALUES (p_order, 'awaiting_payment', 'payment_confirmed', 'customer', 'paid from wallet');

  RETURN jsonb_build_object('ok', true, 'charged', v_amount);
END;
$$;
REVOKE ALL ON FUNCTION public.gas_pay_wallet(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gas_pay_wallet(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
