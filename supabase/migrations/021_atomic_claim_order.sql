-- Migration 021: Atomic order claim function
-- Prevents two drivers from accepting the same order (race condition)

CREATE OR REPLACE FUNCTION claim_order(p_order_id UUID, p_driver_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  rows_updated INT;
BEGIN
  UPDATE orders
  SET driver_id = p_driver_id,
      status = 'picked_up',
      updated_at = NOW()
  WHERE id = p_order_id
    AND driver_id IS NULL;
  
  GET DIAGNOSTICS rows_updated = ROW_COUNT;
  RETURN rows_updated > 0;
END;
$$;
