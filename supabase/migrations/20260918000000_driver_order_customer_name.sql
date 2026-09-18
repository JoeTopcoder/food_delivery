-- Give a driver the customer's name for an order they can actually see (their
-- assigned/active delivery, or an available unassigned order), so the driver
-- app can show an abbreviated "J Scott" on delivery screens. SECURITY DEFINER
-- so it can read users.name; access is gated to the requesting driver, and it
-- returns only the name (no other PII).
CREATE OR REPLACE FUNCTION public.get_order_customer_name(p_order_id uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_name text;
  v_ok   boolean;
BEGIN
  IF v_uid IS NULL THEN
    RETURN 'Customer';
  END IF;

  -- The caller must be a driver who is either assigned to this order or is
  -- looking at it while it is available to accept.
  SELECT EXISTS (
    SELECT 1
    FROM orders o
    JOIN drivers d ON d.user_id = v_uid
    WHERE o.id = p_order_id
      AND (
        o.driver_id = d.id
        OR (o.driver_id IS NULL
            AND o.status IN ('pending','confirmed','preparing','ready'))
      )
  ) INTO v_ok;

  IF NOT v_ok THEN
    RETURN 'Customer';
  END IF;

  SELECT u.name INTO v_name
  FROM orders o
  JOIN users u ON u.id = o.user_id
  WHERE o.id = p_order_id;

  RETURN COALESCE(NULLIF(trim(v_name), ''), 'Customer');
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_order_customer_name(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
