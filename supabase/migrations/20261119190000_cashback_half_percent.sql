-- Change order cashback from 3% to 0.5%, and make the rate configurable via
-- app_config('cashback_rate'). Credited to wallets.cashback_balance on delivery
-- (unchanged mechanism; same trigger auto_cashback_on_delivery → this fn).
INSERT INTO public.app_config (key, value, value_type)
VALUES ('cashback_rate', '0.005', 'string')
ON CONFLICT (key) DO UPDATE SET value = '0.005';

CREATE OR REPLACE FUNCTION public.wallet_award_cashback(p_user_id uuid, p_order_id uuid, p_subtotal numeric)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_rate     numeric;
  v_cashback numeric;
BEGIN
  SELECT COALESCE((SELECT value::numeric FROM public.app_config WHERE key = 'cashback_rate'), 0.005)
    INTO v_rate;
  v_cashback := ROUND(p_subtotal * v_rate, 2);
  IF v_cashback <= 0 THEN RETURN; END IF;

  INSERT INTO public.wallets (user_id, cashback_balance) VALUES (p_user_id, v_cashback)
  ON CONFLICT (user_id) DO UPDATE SET
    cashback_balance = public.wallets.cashback_balance + v_cashback,
    updated_at = now();

  INSERT INTO public.wallet_transactions (user_id, amount, type, payment_method, status, order_id, description)
  VALUES (p_user_id, v_cashback, 'cashback', 'system', 'completed', p_order_id,
    TRIM(TO_CHAR(v_rate * 100, 'FM999990.0##')) || '% cashback on order #' || UPPER(LEFT(p_order_id::text, 8)));
END;
$function$;

NOTIFY pgrst, 'reload schema';
