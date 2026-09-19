-- Proper dispatching cap: a driver may hold at most 3 orders at once. Enforce
-- it inside the atomic claim so a stale client or two simultaneous accepts can
-- never push a driver past 3. A per-driver advisory lock serializes concurrent
-- claims by the same driver, so the count check and the claim are effectively
-- one atomic step.
CREATE OR REPLACE FUNCTION public.claim_order(p_order_id uuid, p_driver_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  rows_updated INT;
  v_active     INT;
BEGIN
  -- Serialize claims by this driver for the rest of the transaction.
  PERFORM pg_advisory_xact_lock(hashtext(p_driver_id::text));

  SELECT count(*) INTO v_active
  FROM orders
  WHERE driver_id = p_driver_id
    AND status NOT IN ('delivered', 'cancelled');

  IF v_active >= 3 THEN
    RETURN false;  -- already at the 3-order max
  END IF;

  UPDATE orders
  SET driver_id = p_driver_id,
      status = 'picked_up',
      updated_at = NOW()
  WHERE id = p_order_id
    AND driver_id IS NULL
    AND is_pickup = FALSE;

  GET DIAGNOSTICS rows_updated = ROW_COUNT;
  RETURN rows_updated > 0;
END;
$function$;

NOTIFY pgrst, 'reload schema';
