-- ============================================================================
-- SECURITY HARDENING — close remotely-exploitable money holes
-- ============================================================================
-- Root cause: several SECURITY DEFINER money functions were granted EXECUTE to
-- anon/authenticated/public and trusted their caller-supplied id/amount args
-- instead of auth.uid(). The anon key ships inside the app, so these were
-- callable by anyone. Two-part fix: (1) revoke server-only functions from
-- client roles; (2) pin caller identity inside client-callable functions and
-- reject the anon key. Mirrors the proven require_admin() pattern.

-- ── Identity helper: reject anon; JWT users are pinned to their own uid;
--    service_role / direct SQL (no JWT) keep the passed id (already trusted). ──
CREATE OR REPLACE FUNCTION public.pin_to_caller(p_claimed uuid)
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_role TEXT := COALESCE(auth.role(), '');
  v_uid  UUID := auth.uid();
BEGIN
  IF v_role = 'anon' THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF v_uid IS NOT NULL THEN
    RETURN v_uid;                 -- JWT user: can only ever act as themselves
  END IF;
  RETURN p_claimed;               -- service_role / direct SQL: trusted
END; $$;
REVOKE ALL ON FUNCTION public.pin_to_caller(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.pin_to_caller(uuid) TO authenticated, service_role;

-- ============================================================================
-- PART 1 — server-only money functions: revoke every client role.
-- These are never called from the app (verified against lib/); only edge
-- functions (service_role) and internal triggers invoke them.
-- ============================================================================
REVOKE EXECUTE ON FUNCTION public.increment_cash_float(uuid, numeric)                       FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.apply_driver_float_change(uuid, numeric, text, uuid, text) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.activate_membership(uuid, uuid, text)                      FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.collect_cod_to_float(uuid, uuid)                           FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.pay_restaurant_from_float(uuid, uuid)                      FROM PUBLIC, anon, authenticated;

-- search_path hardening for the two SECURITY DEFINER funcs that lacked it.
ALTER FUNCTION public.increment_cash_float(uuid, numeric)                       SET search_path = public;
ALTER FUNCTION public.apply_driver_float_change(uuid, numeric, text, uuid, text) SET search_path = public;

-- ============================================================================
-- PART 2 — client-callable functions: pin identity + reject anon.
-- ============================================================================

-- credit_earning: the ONLY client caller is the admin "adjust credit" tool;
-- referral crediting is server-side (service_role). So require admin for JWT
-- callers, allow service_role/direct SQL, reject everyone else.
CREATE OR REPLACE FUNCTION public.credit_earning(p_user_id uuid, p_amount numeric, p_type text, p_source_user uuid DEFAULT NULL::uuid, p_order_id uuid DEFAULT NULL::uuid, p_description text DEFAULT ''::text, p_expiry_days integer DEFAULT NULL::integer)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_monthly_cap     DECIMAL;
  v_current_monthly DECIMAL;
  v_month_key       TEXT := to_char(now(), 'YYYY-MM');
  v_final_amount    DECIMAL;
  v_expires_at      TIMESTAMPTZ;
  v_txn_id          UUID;
  v_expiry_days     INT;
BEGIN
  -- SECURITY: block the anon key; JWT callers must be admin (service_role/direct
  -- SQL bypasses for server-side referral crediting).
  IF COALESCE(auth.role(),'') = 'anon' THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin only';
  END IF;

  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'Amount must be positive';
  END IF;

  -- Get monthly cap from config
  SELECT COALESCE(
    (SELECT value::decimal FROM app_config WHERE key = 'earning_monthly_cap'),
    300.00
  ) INTO v_monthly_cap;

  -- Get or reset monthly earned for this user
  INSERT INTO earning_accounts (user_id, monthly_earned, month_key)
  VALUES (p_user_id, 0, v_month_key)
  ON CONFLICT (user_id) DO UPDATE SET
    monthly_earned = CASE
      WHEN earning_accounts.month_key != v_month_key THEN 0
      ELSE earning_accounts.monthly_earned
    END,
    month_key = v_month_key,
    updated_at = now();

  SELECT monthly_earned INTO v_current_monthly
  FROM earning_accounts WHERE user_id = p_user_id;

  -- Cap the amount so user doesn't exceed monthly limit
  v_final_amount := LEAST(p_amount, v_monthly_cap - v_current_monthly);
  IF v_final_amount <= 0 THEN
    RAISE EXCEPTION 'Monthly earning cap reached';
  END IF;

  -- Calculate expiry
  IF p_expiry_days IS NOT NULL THEN
    v_expiry_days := p_expiry_days;
  ELSE
    SELECT COALESCE(
      (SELECT value::int FROM app_config WHERE key = 'earning_credit_expiry_days'),
      21
    ) INTO v_expiry_days;
  END IF;
  v_expires_at := now() + (v_expiry_days || ' days')::interval;

  -- Insert earning transaction
  INSERT INTO earning_transactions (
    user_id, type, amount, source_user_id, order_id,
    description, expires_at
  ) VALUES (
    p_user_id, p_type, v_final_amount, p_source_user, p_order_id,
    p_description, v_expires_at
  ) RETURNING id INTO v_txn_id;

  -- Credit user's wallet cashback_balance
  INSERT INTO wallets (user_id, balance, cashback_balance)
  VALUES (p_user_id, 0, v_final_amount)
  ON CONFLICT (user_id) DO UPDATE SET
    cashback_balance = wallets.cashback_balance + v_final_amount,
    updated_at = now();

  -- Update earning account stats
  UPDATE earning_accounts SET
    total_earned = total_earned + v_final_amount,
    monthly_earned = monthly_earned + v_final_amount,
    updated_at = now()
  WHERE user_id = p_user_id;

  -- Log wallet transaction
  INSERT INTO wallet_transactions (
    user_id, amount, type, payment_method, status, order_id, description
  ) VALUES (
    p_user_id, v_final_amount, 'cashback', 'system', 'completed',
    p_order_id,
    'Referral earning: ' || p_description
  );

  RETURN v_txn_id;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.credit_earning(uuid, numeric, text, uuid, uuid, text, integer) FROM PUBLIC, anon;

-- add_loyalty_points: customer earns/redeems for THEMSELVES. Pin the account to
-- the caller so nobody can grant points to another user; reject anon.
CREATE OR REPLACE FUNCTION public.add_loyalty_points(p_user_id uuid, p_points integer, p_order_id uuid DEFAULT NULL::uuid, p_type text DEFAULT 'earn'::text, p_description text DEFAULT ''::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_abs_points INTEGER := ABS(p_points);
BEGIN
  -- SECURITY: reject anon; JWT callers may only affect their own account.
  p_user_id := public.pin_to_caller(p_user_id);

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
REVOKE EXECUTE ON FUNCTION public.add_loyalty_points(uuid, integer, uuid, text, text) FROM PUBLIC, anon;

-- checkout_clear_debt_direct: pin to caller + reject anon.
CREATE OR REPLACE FUNCTION public.checkout_clear_debt_direct(p_user_id uuid, p_amount numeric, p_reference text DEFAULT 'checkout'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_debt   DECIMAL;
  v_clear  DECIMAL;
BEGIN
  p_user_id := public.pin_to_caller(p_user_id);
  IF p_amount <= 0 THEN RETURN; END IF;

  SELECT COALESCE(debt_balance, 0) INTO v_debt
  FROM wallets WHERE user_id = p_user_id FOR UPDATE;

  IF v_debt IS NULL OR v_debt <= 0 THEN RETURN; END IF;
  v_clear := LEAST(p_amount, v_debt);

  UPDATE wallets
  SET debt_balance = GREATEST(0, debt_balance - v_clear), updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions (user_id, amount, type, status, description)
  VALUES (p_user_id, -v_clear, 'debt_clearance', 'completed',
     'Outstanding balance cleared at checkout (' || p_reference || ')');

  UPDATE wallet_adjustments SET applied = true
  WHERE user_id = p_user_id AND type = 'debt' AND applied = false;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.checkout_clear_debt_direct(uuid, numeric, text) FROM PUBLIC, anon;

-- checkout_settle_debt: pin to caller + reject anon.
CREATE OR REPLACE FUNCTION public.checkout_settle_debt(p_user_id uuid, p_reference text DEFAULT 'checkout'::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_debt    DECIMAL;
  v_balance DECIMAL;
  v_settle  DECIMAL;
BEGIN
  p_user_id := public.pin_to_caller(p_user_id);

  SELECT COALESCE(debt_balance, 0), COALESCE(balance, 0)
  INTO v_debt, v_balance
  FROM wallets WHERE user_id = p_user_id FOR UPDATE;

  IF v_debt IS NULL OR v_debt <= 0 THEN RETURN 0; END IF;
  v_settle := LEAST(v_debt, v_balance);
  IF v_settle <= 0 THEN RETURN 0; END IF;

  UPDATE wallets
  SET balance = balance - v_settle, debt_balance = debt_balance - v_settle,
      updated_at = NOW()
  WHERE user_id = p_user_id;

  INSERT INTO wallet_transactions (user_id, amount, type, status, description)
  VALUES (p_user_id, -v_settle, 'debt_clearance', 'completed',
     'Outstanding balance settled from wallet (' || p_reference || ')');

  RETURN v_settle;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.checkout_settle_debt(uuid, text) FROM PUBLIC, anon;

-- cancel_order_with_penalty: pin the order owner to the caller + reject anon.
CREATE OR REPLACE FUNCTION public.cancel_order_with_penalty(p_order_id uuid, p_user_id uuid, p_refund_method text DEFAULT 'original'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order orders;
  v_minutes_passed DOUBLE PRECISION;
  v_penalty DECIMAL := 0;
  v_refund DECIMAL := 0;
  v_result TEXT;
  v_refund_method TEXT := COALESCE(NULLIF(p_refund_method, ''), 'original');
BEGIN
  p_user_id := public.pin_to_caller(p_user_id);

  SELECT * INTO v_order
  FROM orders
  WHERE id = p_order_id AND user_id = p_user_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  IF v_order.status NOT IN ('draft', 'pending', 'confirmed', 'accepted', 'preparing') THEN
    RAISE EXCEPTION 'Cannot cancel order in status: %', v_order.status;
  END IF;

  IF v_refund_method NOT IN ('original', 'wallet') THEN
    v_refund_method := 'original';
  END IF;

  v_minutes_passed := EXTRACT(EPOCH FROM (now() - v_order.ordered_at)) / 60.0;

  IF v_minutes_passed < 5 THEN
    v_result := 'cancelled_free';
    v_penalty := 0;
  ELSIF v_order.status = 'preparing' THEN
    v_penalty := ROUND((v_order.total_amount * 0.15)::numeric, 2);
    v_result := 'cancelled_with_fee';
  ELSE
    v_penalty := 1.00;
    v_result := 'cancelled_with_fee';
  END IF;

  UPDATE orders
  SET status = 'cancelled', updated_at = now()
  WHERE id = p_order_id;

  INSERT INTO wallets (user_id)
  VALUES (p_user_id)
  ON CONFLICT (user_id) DO NOTHING;

  IF v_order.payment_method = 'wallet' THEN
    v_refund := GREATEST((v_order.total_amount - v_penalty)::numeric, 0);
    v_refund_method := 'wallet';

    IF v_refund > 0 THEN
      UPDATE wallets
      SET balance = balance + v_refund, updated_at = now()
      WHERE user_id = p_user_id;

      INSERT INTO wallet_transactions (
        user_id, amount, type, payment_method, status, order_id, description
      )
      VALUES (
        p_user_id, v_refund, 'refund', 'wallet', 'completed', p_order_id,
        CASE WHEN v_penalty > 0
          THEN 'Refund for order #' || UPPER(LEFT(p_order_id::text, 8)) || ' (minus $' || v_penalty::text || ' fee)'
          ELSE 'Full refund for order #' || UPPER(LEFT(p_order_id::text, 8))
        END
      );
    END IF;

  ELSIF v_order.payment_method = 'card' THEN
    v_refund := GREATEST((v_order.total_amount - v_penalty)::numeric, 0);

    IF v_refund_method = 'wallet' AND v_refund > 0 THEN
      UPDATE wallets
      SET balance = balance + v_refund, updated_at = now()
      WHERE user_id = p_user_id;

      INSERT INTO wallet_transactions (
        user_id, amount, type, payment_method, status, order_id, description
      )
      VALUES (
        p_user_id, v_refund, 'refund', 'wallet', 'completed', p_order_id,
        CASE WHEN v_penalty > 0
          THEN 'Card order refund to wallet for order #' || UPPER(LEFT(p_order_id::text, 8)) || ' (minus $' || v_penalty::text || ' fee)'
          ELSE 'Card order refund to wallet for order #' || UPPER(LEFT(p_order_id::text, 8))
        END
      );

      UPDATE orders
      SET payment_status = 'refunded', updated_at = now()
      WHERE id = p_order_id;
    ELSE
      v_refund_method := 'original';
    END IF;

  ELSIF v_order.payment_method = 'cash' THEN
    v_refund := 0;
    v_refund_method := 'none';
  ELSE
    v_refund := 0;
    v_refund_method := 'none';
  END IF;

  IF v_penalty > 0 AND v_order.driver_id IS NOT NULL THEN
    INSERT INTO wallets (user_id, balance)
    VALUES (v_order.driver_id, v_penalty)
    ON CONFLICT (user_id) DO UPDATE SET
      balance = wallets.balance + v_penalty, updated_at = now();

    INSERT INTO wallet_transactions (
      user_id, amount, type, payment_method, status, order_id, description
    )
    VALUES (
      v_order.driver_id, v_penalty, 'tip_received', 'system', 'completed',
      p_order_id, 'Cancellation compensation'
    );
  END IF;

  RETURN jsonb_build_object(
    'result', v_result,
    'penalty', v_penalty,
    'refund', v_refund,
    'refund_method', v_refund_method,
    'payment_method', v_order.payment_method,
    'total_amount', v_order.total_amount,
    'minutes_passed', ROUND(v_minutes_passed::numeric, 1)
  );
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.cancel_order_with_penalty(uuid, uuid, text) FROM PUBLIC, anon;

-- claim_order: a driver may only claim on behalf of their OWN driver profile.
CREATE OR REPLACE FUNCTION public.claim_order(p_order_id uuid, p_driver_id uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  rows_updated INT;
  v_active     INT;
BEGIN
  -- SECURITY: reject anon; a JWT caller must own the driver profile.
  IF COALESCE(auth.role(),'') = 'anon' THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF auth.uid() IS NOT NULL AND NOT EXISTS (
       SELECT 1 FROM drivers WHERE id = p_driver_id AND user_id = auth.uid()) THEN
    RAISE EXCEPTION 'Not your driver profile';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(p_driver_id::text));

  SELECT count(*) INTO v_active
  FROM orders
  WHERE driver_id = p_driver_id
    AND status NOT IN ('delivered', 'cancelled');

  IF v_active >= 3 THEN
    RETURN false;
  END IF;

  UPDATE orders
  SET driver_id = p_driver_id, status = 'picked_up', updated_at = NOW()
  WHERE id = p_order_id AND driver_id IS NULL AND is_pickup = FALSE;

  GET DIAGNOSTICS rows_updated = ROW_COUNT;
  RETURN rows_updated > 0;
END;
$function$;
REVOKE EXECUTE ON FUNCTION public.claim_order(uuid, uuid) FROM PUBLIC, anon;

-- ============================================================================
-- PART 3 — RLS: ai_voice_sessions had a policy named "Service role full access"
-- applied to PUBLIC with USING(true)/WITH CHECK(true) — any user could read or
-- delete everyone's voice transcripts. Restrict to service_role; let a signed-in
-- user read only their own rows.
-- ============================================================================
DROP POLICY IF EXISTS "Service role full access" ON public.ai_voice_sessions;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='ai_voice_sessions' AND policyname='ai_voice_sessions_service_all') THEN
    CREATE POLICY ai_voice_sessions_service_all ON public.ai_voice_sessions
      FOR ALL TO service_role USING (true) WITH CHECK (true);
  END IF;
  IF EXISTS (SELECT 1 FROM information_schema.columns
             WHERE table_schema='public' AND table_name='ai_voice_sessions' AND column_name='user_id')
     AND NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public'
                 AND tablename='ai_voice_sessions' AND policyname='ai_voice_sessions_owner_read') THEN
    CREATE POLICY ai_voice_sessions_owner_read ON public.ai_voice_sessions
      FOR SELECT TO authenticated USING (user_id = auth.uid());
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';
