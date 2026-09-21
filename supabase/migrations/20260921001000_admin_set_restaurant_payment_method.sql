-- Admin-only setter for a restaurant's payment method (CASH_PAYMENT /
-- BANK_PAYMENT). Only affects FUTURE orders — existing orders keep their
-- immutable snapshot.
CREATE OR REPLACE FUNCTION public.admin_set_restaurant_payment_method(
  p_restaurant_id uuid,
  p_method        text
)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin') THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;
  IF p_method NOT IN ('CASH_PAYMENT','BANK_PAYMENT') THEN
    RAISE EXCEPTION 'invalid payment method: %', p_method;
  END IF;

  UPDATE restaurants
     SET restaurant_payment_method = p_method, updated_at = now()
   WHERE id = p_restaurant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'restaurant % not found', p_restaurant_id;
  END IF;
  RETURN p_method;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_restaurant_payment_method(uuid, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_restaurant_payment_method(uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';
