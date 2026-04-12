-- Atomic cash_float increment to prevent race conditions
CREATE OR REPLACE FUNCTION increment_cash_float(p_driver_id UUID, p_amount NUMERIC)
RETURNS VOID AS $$
BEGIN
  UPDATE drivers
  SET cash_float = COALESCE(cash_float, 0) + p_amount,
      updated_at = NOW()
  WHERE id = p_driver_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
