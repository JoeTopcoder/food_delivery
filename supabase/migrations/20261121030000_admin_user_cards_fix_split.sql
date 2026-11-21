-- Correct split: TOP-UPS are the actual wallet deposits (wallet_transactions
-- type='deposit'); VERIFICATION charges are ALL card_verifications rows (the
-- test-charge used to verify a card). The earlier pi_/seti_ split wrongly put a
-- verification charge under top-ups.
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
    -- TOP-UPS: money that actually landed in the wallet.
    'card_topups', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'amount', amount, 'method', payment_method, 'status', status,
        'description', description, 'created_at', created_at
      ) ORDER BY created_at DESC) FROM public.wallet_transactions
      WHERE user_id = p_user_id AND type = 'deposit'), '[]'::jsonb),
    -- VERIFICATION charges: the test-charge used to verify/add a card.
    'card_verifications', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'brand', card_brand, 'last4', card_last4, 'amount', amount,
        'currency', currency, 'status', status, 'refund_status', refund_status,
        'created_at', created_at
      ) ORDER BY created_at DESC) FROM public.card_verifications
      WHERE user_id = p_user_id), '[]'::jsonb)
  ) INTO v_result;
  RETURN v_result;
END;
$$;
NOTIFY pgrst, 'reload schema';
