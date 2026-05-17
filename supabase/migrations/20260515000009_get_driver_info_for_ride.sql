-- RPC: get_driver_info_for_ride
-- Allows a customer to fetch their assigned driver's name and vehicle info
-- without being blocked by users/drivers RLS policies.
-- SECURITY DEFINER so it reads across tables as the function owner.

CREATE OR REPLACE FUNCTION public.get_driver_info_for_ride(p_ride_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id uuid;
  v_driver_id   uuid;
  v_result      jsonb;
BEGIN
  -- Look up the ride
  SELECT customer_id, driver_id
  INTO v_customer_id, v_driver_id
  FROM ride_requests
  WHERE id = p_ride_id;

  IF NOT FOUND THEN
    RETURN NULL;
  END IF;

  -- Only the customer of this ride may call this function
  IF v_customer_id IS DISTINCT FROM auth.uid() THEN
    RETURN NULL;
  END IF;

  IF v_driver_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT jsonb_build_object(
    'name',          COALESCE(NULLIF(TRIM(u.name), ''), SPLIT_PART(u.email, '@', 1), 'Your Driver'),
    'rating',        d.rating,
    'vehicle_make',  COALESCE(d.vehicle_make,  ''),
    'vehicle_model', COALESCE(d.vehicle_model, ''),
    'vehicle_color', COALESCE(d.vehicle_color, ''),
    'plate_number',  COALESCE(d.plate_number,  ''),
    'vehicle_type',  COALESCE(d.vehicle_type,  '')
  )
  INTO v_result
  FROM drivers d
  LEFT JOIN users u ON u.id = d.user_id
  WHERE d.id = v_driver_id;

  RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_driver_info_for_ride(uuid) TO authenticated;
