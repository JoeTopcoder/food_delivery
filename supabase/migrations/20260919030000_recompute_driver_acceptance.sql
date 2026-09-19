-- Recompute a driver's acceptance / decline stats directly in Postgres, so the
-- decline rate updates reliably the moment a driver declines — independent of
-- the heavier driver-intelligence edge function (which also recomputes these
-- but has been failing to boot). Uses the same 30-day window and the same
-- accepted/(accepted+declined) formula as that function.
CREATE OR REPLACE FUNCTION public.recompute_driver_acceptance(p_driver_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_accepted integer;
  v_declined integer;
  v_rate     numeric;
BEGIN
  IF p_driver_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT count(*) INTO v_accepted
  FROM orders
  WHERE driver_id = p_driver_id
    AND status = 'delivered'
    AND ordered_at >= now() - interval '30 days';

  SELECT count(*) INTO v_declined
  FROM driver_declined_orders
  WHERE driver_id = p_driver_id
    AND declined_at >= now() - interval '30 days';

  v_rate := CASE
    WHEN (v_accepted + v_declined) > 0
      THEN round((v_accepted::numeric / (v_accepted + v_declined)) * 100, 1)
    ELSE 100
  END;

  INSERT INTO driver_stats (driver_id, orders_accepted, orders_declined,
                            acceptance_rate, updated_at)
  VALUES (p_driver_id, v_accepted, v_declined, v_rate, now())
  ON CONFLICT (driver_id) DO UPDATE SET
    orders_accepted = excluded.orders_accepted,
    orders_declined = excluded.orders_declined,
    acceptance_rate = excluded.acceptance_rate,
    updated_at = now();

  RETURN jsonb_build_object(
    'orders_accepted', v_accepted,
    'orders_declined', v_declined,
    'acceptance_rate', v_rate
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.recompute_driver_acceptance(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
