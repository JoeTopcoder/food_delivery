-- Admin User Management: see a customer's cards on file (added / pending / failed
-- to verify) and their card top-up/charge history (successful + failed). Reads
-- otherwise-private tables via a single admin-guarded RPC.
CREATE OR REPLACE FUNCTION public.admin_get_user_cards(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $$
DECLARE v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Forbidden: admin only' USING ERRCODE='42501'; END IF;

  SELECT jsonb_build_object(
    -- Cards on file: status 'verified' = added OK; 'pending'/'failed' = tried to add.
    'saved_cards', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'brand', card_brand, 'last4', last_four, 'status', status,
        'is_default', is_default, 'exp_month', exp_month, 'exp_year', exp_year,
        'attempts', verification_attempts, 'created_at', created_at
      ) ORDER BY created_at DESC) FROM public.saved_cards WHERE user_id = p_user_id), '[]'::jsonb),
    -- Card charges / top-up attempts: status 'completed' = success, else failed.
    'card_charges', COALESCE((SELECT jsonb_agg(jsonb_build_object(
        'brand', card_brand, 'last4', card_last4, 'amount', amount,
        'currency', currency, 'status', status, 'refund_status', refund_status,
        'created_at', created_at
      ) ORDER BY created_at DESC) FROM public.card_verifications WHERE user_id = p_user_id), '[]'::jsonb),
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
REVOKE ALL ON FUNCTION public.admin_get_user_cards(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_user_cards(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
