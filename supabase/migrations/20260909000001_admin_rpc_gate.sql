-- Migration: gate the admin RPCs on the session, and take them away from anon.
--
-- Every admin RPC was granted to anon. The anon key is compiled into the
-- Flutter binary and is public by design, so "granted to anon" means granted to
-- anyone who downloads the app and reads the string out of it.
--
-- admin_wallet_adjust — which credits wallets — did check for an admin, but
-- against p_admin_id, a value the CALLER supplies. Passing any admin's UUID
-- satisfied it. Anyone could credit any wallet any amount. The other five had
-- no check at all and returned platform-wide financials.
--
-- This is the exact pattern CLAUDE.md documents: SECURITY DEFINER plus a
-- caller-supplied user id is not an authorization check. The fix is the same
-- one wallet_transfer uses — pin to auth.uid(), and fall back to the parameter
-- only when there is no JWT, which is the service-role/direct-SQL case.

-- ── A single place to answer "is the caller an admin?" ─────────────────────
CREATE OR REPLACE FUNCTION public.require_admin(p_fallback UUID DEFAULT NULL)
RETURNS UUID
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_caller UUID := COALESCE(auth.uid(), p_fallback);
BEGIN
  -- auth.uid() wins whenever there is a JWT. p_fallback is only reachable from
  -- service_role or direct SQL, which are already trusted.
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = v_caller AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  RETURN v_caller;
END;
$$;

GRANT EXECUTE ON FUNCTION public.require_admin TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.require_admin FROM anon;

-- ── Close the wallet hole ──────────────────────────────────────────────────
-- Same signature, so no caller changes. p_admin_id is now advisory: the
-- session decides, and it is only consulted when there is no session.
CREATE OR REPLACE FUNCTION public.admin_wallet_adjust(
  p_user_id     UUID,
  p_amount      NUMERIC,
  p_description TEXT,
  p_admin_id    UUID
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin          UUID;
  v_type           TEXT;
  v_abs            DECIMAL;
  v_current_bal    DECIMAL;
  v_deduct_now     DECIMAL;
  v_remaining_debt DECIMAL;
BEGIN
  v_admin := public.require_admin(p_admin_id);

  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  v_abs  := ABS(p_amount);
  v_type := CASE WHEN p_amount >= 0 THEN 'credit' ELSE 'debt' END;

  INSERT INTO wallets (user_id, balance, cashback_balance, debt_balance)
  VALUES (p_user_id, 0, 0, 0)
  ON CONFLICT (user_id) DO NOTHING;

  IF v_type = 'credit' THEN
    UPDATE wallets
       SET balance = balance + v_abs, updated_at = NOW()
     WHERE user_id = p_user_id;

    INSERT INTO wallet_transactions (user_id, amount, type, status, description)
    VALUES (p_user_id, v_abs, 'admin_credit', 'completed', p_description);
  ELSE
    SELECT balance INTO v_current_bal FROM wallets
     WHERE user_id = p_user_id FOR UPDATE;

    v_deduct_now     := LEAST(COALESCE(v_current_bal, 0), v_abs);
    v_remaining_debt := v_abs - v_deduct_now;

    UPDATE wallets
       SET balance      = COALESCE(balance, 0) - v_deduct_now,
           debt_balance = COALESCE(debt_balance, 0) + v_remaining_debt,
           updated_at   = NOW()
     WHERE user_id = p_user_id;

    IF v_deduct_now > 0 THEN
      -- Debits are stored negative. See CLAUDE.md's ledger sign convention.
      INSERT INTO wallet_transactions (user_id, amount, type, status, description)
      VALUES (p_user_id, -v_deduct_now, 'penalty', 'completed', p_description);
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'adjusted', TRUE,
    'type', v_type,
    'amount', v_abs,
    'by_admin', v_admin
  );
END;
$$;

-- ── Take every admin surface away from anon ────────────────────────────────
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN (
        'admin_wallet_adjust','admin_order_margins','admin_survival_metrics',
        'admin_toggle_user_status','admin_verify_driver','admin_verify_restaurant',
        'admin_review_driver_application','get_analytics_summary',
        'get_platform_commission_summary','get_top_restaurants',
        'get_active_orders_summary','refresh_daily_metrics','refresh_user_metrics'
      )
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
  END LOOP;
END $$;

NOTIFY pgrst, 'reload schema';
