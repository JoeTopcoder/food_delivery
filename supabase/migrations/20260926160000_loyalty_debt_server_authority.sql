-- ============================================================================
-- Server-authoritative loyalty EARN + debt clearing.
-- Follow-up to 20260926150000: those pinned identity but a user could still
-- self-grant loyalty points or wipe their own debt for free. Now a JWT caller
-- must prove a real, paid, caller-owned order for both, idempotently and capped.
-- Admin / service_role (server-side referral & admin tools) bypass the proof.
-- ============================================================================

-- ── Loyalty: earning is tied to a genuine paid order ────────────────────────
CREATE OR REPLACE FUNCTION public.add_loyalty_points(p_user_id uuid, p_points integer, p_order_id uuid DEFAULT NULL::uuid, p_type text DEFAULT 'earn'::text, p_description text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_abs_points  INTEGER := ABS(p_points);
  v_is_jwt_user BOOLEAN := (auth.uid() IS NOT NULL AND NOT public.is_admin());
  v_ord         RECORD;
  v_per100      INTEGER;
  v_max_points  INTEGER;
BEGIN
  -- SECURITY: reject anon; JWT callers may only affect their own account.
  p_user_id := public.pin_to_caller(p_user_id);

  -- Earning must be backed by a real, paid order owned by the caller. This is
  -- what stops a user self-granting arbitrary points. Redeeming (spending your
  -- own points) is not an exploit and is left to the pinned caller.
  IF p_type = 'earn' AND v_is_jwt_user THEN
    IF p_order_id IS NULL THEN
      RAISE EXCEPTION 'Loyalty earning requires an order';
    END IF;

    SELECT user_id, total_amount, payment_status, status
      INTO v_ord
      FROM orders WHERE id = p_order_id;

    IF NOT FOUND OR v_ord.user_id <> p_user_id THEN
      RAISE EXCEPTION 'Order not found for this user';
    END IF;
    IF COALESCE(v_ord.payment_status,'') <> 'completed' THEN
      RAISE EXCEPTION 'Order is not paid';
    END IF;

    -- Idempotent: never award earn twice for the same order.
    IF EXISTS (SELECT 1 FROM loyalty_transactions
               WHERE order_id = p_order_id AND type = 'earn') THEN
      RETURN;
    END IF;

    -- Cap to the server-computed maximum for this order (rate × top tier ×2).
    v_per100 := COALESCE((SELECT value::int FROM app_config WHERE key = 'loyalty_points_per_100'), 3);
    v_max_points := FLOOR(COALESCE(v_ord.total_amount,0) / 100.0)::int * v_per100 * 2;
    IF v_max_points < 0 THEN v_max_points := 0; END IF;
    v_abs_points := LEAST(v_abs_points, v_max_points);

    IF v_abs_points <= 0 THEN RETURN; END IF;
  END IF;

  INSERT INTO loyalty_transactions (user_id, order_id, points, type, description)
  VALUES (p_user_id, p_order_id, v_abs_points, p_type, p_description);

  INSERT INTO loyalty_accounts (user_id, points, total_earned, total_redeemed, updated_at)
  VALUES (
    p_user_id,
    CASE WHEN p_type = 'earn' THEN v_abs_points ELSE 0 END,
    CASE WHEN p_type = 'earn' THEN v_abs_points ELSE 0 END,
    CASE WHEN p_type = 'redeem' THEN v_abs_points ELSE 0 END,
    now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    points = loyalty_accounts.points
             + CASE WHEN p_type = 'earn'   THEN v_abs_points
                    WHEN p_type = 'redeem' THEN -v_abs_points
                    ELSE 0 END,
    total_earned = loyalty_accounts.total_earned
                   + CASE WHEN p_type = 'earn' THEN v_abs_points ELSE 0 END,
    total_redeemed = loyalty_accounts.total_redeemed
                     + CASE WHEN p_type = 'redeem' THEN v_abs_points ELSE 0 END,
    updated_at = now();
END;
$function$;

-- ── Debt clearing must be backed by a genuine paid order ────────────────────
CREATE OR REPLACE FUNCTION public.checkout_clear_debt_direct(p_user_id uuid, p_amount numeric, p_reference text DEFAULT 'checkout'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_debt        DECIMAL;
  v_clear       DECIMAL;
  v_is_jwt_user BOOLEAN := (auth.uid() IS NOT NULL AND NOT public.is_admin());
  v_order_id    UUID;
  v_ord         RECORD;
BEGIN
  p_user_id := public.pin_to_caller(p_user_id);
  IF p_amount <= 0 THEN RETURN; END IF;

  -- A JWT caller can only clear debt against a real, paid order they own, once,
  -- and never more than that order's value. Admin/service_role bypass (edge fns
  -- and admin tools that already proved payment).
  IF v_is_jwt_user THEN
    BEGIN
      v_order_id := p_reference::uuid;
    EXCEPTION WHEN others THEN
      RAISE EXCEPTION 'Debt clearing requires a paid order reference';
    END;

    SELECT user_id, total_amount, payment_status
      INTO v_ord FROM orders WHERE id = v_order_id;

    IF NOT FOUND OR v_ord.user_id <> p_user_id
       OR COALESCE(v_ord.payment_status,'') <> 'completed' THEN
      RAISE EXCEPTION 'Debt clearing requires a paid order you own';
    END IF;

    -- Idempotent: one clearance per order.
    IF EXISTS (SELECT 1 FROM wallet_transactions
               WHERE order_id = v_order_id AND type = 'debt_clearance') THEN
      RETURN;
    END IF;

    -- Never clear more debt than the value actually paid on that order.
    p_amount := LEAST(p_amount, COALESCE(v_ord.total_amount, 0));
    IF p_amount <= 0 THEN RETURN; END IF;
  END IF;

  SELECT COALESCE(debt_balance, 0) INTO v_debt
  FROM wallets WHERE user_id = p_user_id FOR UPDATE;

  IF v_debt IS NULL OR v_debt <= 0 THEN RETURN; END IF;
  v_clear := LEAST(p_amount, v_debt);

  UPDATE wallets
  SET debt_balance = GREATEST(0, debt_balance - v_clear), updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions (user_id, amount, type, status, description, order_id)
  VALUES (p_user_id, -v_clear, 'debt_clearance', 'completed',
     'Outstanding balance cleared at checkout (' || p_reference || ')', v_order_id);

  UPDATE wallet_adjustments SET applied = true
  WHERE user_id = p_user_id AND type = 'debt' AND applied = false;
END;
$function$;

NOTIFY pgrst, 'reload schema';
