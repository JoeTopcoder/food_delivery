-- Migration 089: Fix wallet summary function (LANGUAGE plpgsql was missing in 088)

-- Wallet summary view
CREATE OR REPLACE VIEW public.driver_wallet_summary AS
SELECT
  d.id                       AS driver_id,
  d.user_id,
  d.stripe_account_id,
  d.payouts_enabled,
  d.stripe_debit_card_added,
  d.stripe_account_status,
  COALESCE(d.total_earnings, 0)  AS total_earned,
  COALESCE(d.total_paid_out, 0)  AS total_paid_out,
  GREATEST(0, COALESCE(d.total_earnings, 0) - COALESCE(d.total_paid_out, 0))
                              AS available_balance
FROM public.drivers d;

-- Helper function: driver wallet summary (security definer so drivers can call it)
CREATE OR REPLACE FUNCTION public.get_driver_wallet_summary(p_user_id UUID)
RETURNS TABLE (
  driver_id               UUID,
  stripe_account_id       TEXT,
  payouts_enabled         BOOLEAN,
  stripe_debit_card_added BOOLEAN,
  stripe_account_status   TEXT,
  total_earned            NUMERIC,
  total_paid_out          NUMERIC,
  available_balance       NUMERIC
) SECURITY DEFINER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT
    dws.driver_id,
    dws.stripe_account_id,
    dws.payouts_enabled,
    dws.stripe_debit_card_added,
    dws.stripe_account_status,
    dws.total_earned,
    dws.total_paid_out,
    dws.available_balance
  FROM public.driver_wallet_summary dws
  WHERE dws.user_id = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_driver_wallet_summary(UUID) TO authenticated;
