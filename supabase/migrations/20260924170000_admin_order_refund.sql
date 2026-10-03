-- Admin order refund — audited, over-refund-safe. Records a refunds row and
-- (for wallet refunds) credits the customer's wallet by REUSING the existing
-- audited admin_wallet_adjust RPC, so we never hand-roll a wallet_transactions
-- type (avoids the CHECK-constraint drift documented in CLAUDE.md) and the wallet
-- balance/ledger stay in sync.
--
-- Non-wallet ('manual') refunds only log the refunds row — the money movement
-- (e.g. Stripe reversal or cash) is handled by the human outside the wallet.
CREATE OR REPLACE FUNCTION public.admin_refund_order(
  p_order_id  uuid,
  p_amount    numeric,
  p_reason    text,
  p_admin_id  uuid,
  p_to_wallet boolean DEFAULT true
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_admin     uuid;
  v_user      uuid;
  v_total     numeric;
  v_refunded  numeric;
  v_remaining numeric;
  v_refund_id uuid;
BEGIN
  v_admin := public.require_admin(p_admin_id);   -- same gate as admin_wallet_adjust

  SELECT user_id, total_amount INTO v_user, v_total FROM orders WHERE id = p_order_id;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN RAISE EXCEPTION 'Refund amount must be positive'; END IF;

  -- Prevent over-refunding: sum prior non-rejected refunds for this order.
  SELECT COALESCE(sum(amount), 0) INTO v_refunded
    FROM refunds WHERE order_id = p_order_id AND status IN ('approved','processed');
  v_remaining := COALESCE(v_total, 0) - v_refunded;
  IF p_amount > v_remaining + 0.001 THEN
    RAISE EXCEPTION 'Refund % exceeds refundable remaining %', round(p_amount,2), round(v_remaining,2);
  END IF;

  INSERT INTO refunds (order_id, user_id, amount, reason, status, refund_method, admin_notes, processed_at)
  VALUES (p_order_id, v_user, p_amount, COALESCE(p_reason,'Admin refund'), 'processed',
          CASE WHEN p_to_wallet THEN 'wallet' ELSE 'manual' END,
          'Admin refund by ' || v_admin, now())
  RETURNING id INTO v_refund_id;

  -- Wallet refunds go through the audited adjust RPC (positive = credit).
  IF p_to_wallet THEN
    PERFORM public.admin_wallet_adjust(
      v_user, p_amount,
      'Refund for order ' || left(p_order_id::text, 8) || COALESCE(' — ' || p_reason, ''),
      p_admin_id);
  END IF;

  -- Member Referral Rewards: if this refund makes the order no longer a
  -- qualifying order, reverse any referral rewards it generated (clawing back
  -- the wallet safely, freeing cap usage). referral_reverse_order is idempotent.
  BEGIN
    IF NOT public.referral_order_qualifies(p_order_id) THEN
      PERFORM public.referral_reverse_order(p_order_id, 'order_refund');
    END IF;
  EXCEPTION WHEN undefined_function THEN
    NULL; -- referral programme not installed in this environment
  END;

  RETURN jsonb_build_object(
    'refunded', true, 'refund_id', v_refund_id, 'amount', p_amount,
    'to_wallet', p_to_wallet, 'remaining_refundable', v_remaining - p_amount, 'by_admin', v_admin);
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_refund_order(uuid, numeric, text, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_refund_order(uuid, numeric, text, uuid, boolean) TO authenticated;

-- Read helper: how much of an order has already been refunded (admin UI).
CREATE OR REPLACE FUNCTION public.admin_order_refunded_total(p_order_id uuid)
RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$ SELECT COALESCE(sum(amount),0) FROM refunds WHERE order_id=p_order_id AND status IN ('approved','processed'); $$;
GRANT EXECUTE ON FUNCTION public.admin_order_refunded_total(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
