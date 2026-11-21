-- Split a customer's card activity into TOP-UPS (real card charges, Stripe
-- PaymentIntent pi_*) vs VERIFICATION charges (card setup/add, SetupIntent
-- seti_* — usually $0). Keeps saved cards + completed wallet deposits.
CREATE OR REPLACE FUNCTION public.admin_get_user_cards(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden: admin only' USING ERRCODE='42501'; END IF;

  SELECT jsonb_build_object(
    'saved_cards', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'brand', card_brand, 'last4', last_four, 'status', status,
        'is_default', is_default, 'exp_month', exp_month, 'exp_year', exp_year,
        'attempts', verification_attempts, 'created_at', created_at
      ) ORDER BY created_at DESC) FROM public.saved_cards WHERE user_id = p_user_id), '[]'::jsonb),
    -- Card TOP-UPS: actual charges (Stripe PaymentIntent pi_*).
    'card_topups', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'brand', card_brand, 'last4', card_last4, 'amount', amount,
        'currency', currency, 'status', status, 'refund_status', refund_status,
        'created_at', created_at
      ) ORDER BY created_at DESC)
      FROM public.card_verifications
      WHERE user_id = p_user_id AND COALESCE(transaction_id,'') ILIKE 'pi\_%'), '[]'::jsonb),
    -- Card VERIFICATIONS: card setup/add (SetupIntent seti_* or non-charge).
    'card_verifications', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'brand', card_brand, 'last4', card_last4, 'amount', amount,
        'currency', currency, 'status', status, 'refund_status', refund_status,
        'created_at', created_at
      ) ORDER BY created_at DESC)
      FROM public.card_verifications
      WHERE user_id = p_user_id AND COALESCE(transaction_id,'') NOT ILIKE 'pi\_%'), '[]'::jsonb),
    -- Completed wallet deposits (money that landed in the wallet).
    'topups', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'amount', amount, 'method', payment_method, 'status', status,
        'description', description, 'created_at', created_at
      ) ORDER BY created_at DESC) FROM public.wallet_transactions
      WHERE user_id = p_user_id AND type = 'deposit'), '[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END;
$$;
NOTIFY pgrst, 'reload schema';
