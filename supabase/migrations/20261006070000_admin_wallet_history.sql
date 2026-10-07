-- Admin-only view of a customer's wallet: authoritative balance + transaction
-- history. Read-only; records nothing and moves no money. (RLS already lets
-- admins read wallet_transactions; this is a clean single-call projection.)
CREATE OR REPLACE FUNCTION public.admin_wallet_history(p_user uuid, p_limit int DEFAULT 100)
  RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE w public.wallets; j jsonb;
BEGIN
  IF NOT public.is_admin() THEN RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  SELECT * INTO w FROM public.wallets WHERE user_id = p_user;
  SELECT coalesce(jsonb_agg(t ORDER BY t.created_at DESC), '[]'::jsonb) INTO j
  FROM (
    SELECT id, amount, type, payment_method, status, order_id, description, created_at
    FROM public.wallet_transactions
    WHERE user_id = p_user
    ORDER BY created_at DESC
    LIMIT greatest(1, least(p_limit, 500))
  ) t;
  RETURN jsonb_build_object(
    'ok', true,
    'balance', coalesce(w.balance,0),
    'cashback_balance', coalesce(w.cashback_balance,0),
    'debt_balance', coalesce(w.debt_balance,0),
    'reserved_balance', coalesce(w.reserved_balance,0),
    'currency', coalesce((SELECT value FROM public.app_config WHERE key='currency_code'),'JMD'),
    'transactions', j);
END; $$;
REVOKE ALL ON FUNCTION public.admin_wallet_history(uuid,int) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_wallet_history(uuid,int) TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';
