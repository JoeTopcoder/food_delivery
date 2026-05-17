-- Change cancellation fee from driver_earning (~80% of fare) to 50% of estimated fare.
-- Clear waiting_started_at the moment the driver resumes (ride_paused → ride_started)
-- so the fee NEVER accumulates past the resume timestamp, regardless of whether the
-- charge-pause-fee edge function ran successfully.

CREATE OR REPLACE FUNCTION update_ride_status(
  p_ride_id        UUID,
  p_new_status     TEXT             DEFAULT NULL,
  p_latitude       DOUBLE PRECISION DEFAULT NULL,
  p_longitude      DOUBLE PRECISION DEFAULT NULL,
  p_pin            TEXT             DEFAULT NULL,
  p_pause_reason   TEXT             DEFAULT NULL,
  p_start_waiting  BOOLEAN          DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id          UUID;
  v_ride             ride_requests%ROWTYPE;
  v_driver_id        UUID;
  v_is_customer      BOOLEAN;
  v_is_driver        BOOLEAN;
  v_is_admin         BOOLEAN;
  v_valid_transition BOOLEAN;
  v_waiting_mins     NUMERIC;
  v_fee_cap          TIMESTAMPTZ;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT * INTO v_ride FROM ride_requests WHERE id = p_ride_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Ride not found';
  END IF;

  SELECT id INTO v_driver_id FROM drivers WHERE user_id = v_user_id;

  v_is_customer := (v_ride.customer_id = v_user_id);
  v_is_driver   := (v_ride.driver_id IS NOT NULL AND v_driver_id IS NOT NULL AND v_driver_id = v_ride.driver_id);
  v_is_admin    := EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND role = 'admin');

  IF NOT (v_is_customer OR v_is_driver OR v_is_admin OR v_driver_id IS NOT NULL) THEN
    RAISE EXCEPTION 'Unauthorized to update this ride';
  END IF;

  -- start_waiting branch
  IF p_start_waiting THEN
    IF NOT (v_is_driver OR v_is_admin) THEN
      RAISE EXCEPTION 'Only the assigned driver can start the waiting fee';
    END IF;
    UPDATE ride_requests
       SET waiting_started_at  = NOW(),
           waiting_fee_per_min = 75.0
     WHERE id = p_ride_id;
    RETURN jsonb_build_object('message', 'Waiting fee started', 'rate', 75.0);
  END IF;

  -- Normal status transition
  IF p_new_status IS NULL THEN
    RAISE EXCEPTION 'new_status is required';
  END IF;

  v_valid_transition := CASE v_ride.ride_status
    WHEN 'requested'        THEN p_new_status = ANY(ARRAY['searching_driver','cancelled'])
    WHEN 'searching_driver' THEN p_new_status = ANY(ARRAY['driver_assigned','cancelled'])
    WHEN 'driver_assigned'  THEN p_new_status = ANY(ARRAY['driver_arriving','driver_arrived','cancelled'])
    WHEN 'driver_arriving'  THEN p_new_status = ANY(ARRAY['driver_arrived','cancelled'])
    WHEN 'driver_arrived'   THEN p_new_status = ANY(ARRAY['ride_started','cancelled'])
    WHEN 'ride_started'     THEN p_new_status = ANY(ARRAY['ride_completed','cancelled','ride_paused'])
    WHEN 'ride_paused'      THEN p_new_status = ANY(ARRAY['ride_started','cancelled'])
    ELSE FALSE
  END;

  IF NOT COALESCE(v_valid_transition, FALSE) THEN
    RAISE EXCEPTION 'Invalid status transition from % to %', v_ride.ride_status, p_new_status;
  END IF;

  -- PIN check: only on initial start (driver_arrived -> ride_started), not resume
  IF p_new_status = 'ride_started' AND v_ride.ride_status = 'driver_arrived' THEN
    IF p_pin IS NULL OR trim(p_pin) != trim(COALESCE(v_ride.ride_pin, '')) THEN
      RAISE EXCEPTION 'Invalid PIN. Ask the customer for their 6-digit code.';
    END IF;
  END IF;

  -- Cancellation fee: 50% of estimated fare + any accrued waiting fee
  -- Waiting fee is capped at started_at to prevent it accumulating past resume.
  IF p_new_status = 'cancelled' AND v_is_customer
     AND v_ride.ride_status = ANY(ARRAY['driver_assigned','driver_arriving','driver_arrived','ride_started','ride_paused'])
  THEN
    v_fee_cap := COALESCE(v_ride.started_at, NOW());
    IF v_ride.waiting_started_at IS NOT NULL THEN
      v_waiting_mins := GREATEST(0,
        EXTRACT(EPOCH FROM (v_fee_cap - v_ride.waiting_started_at)) / 60
      );
    ELSE
      v_waiting_mins := 0;
    END IF;
  END IF;

  UPDATE ride_requests SET
    ride_status         = p_new_status,
    accepted_at         = CASE WHEN p_new_status = 'driver_arriving' THEN NOW() ELSE accepted_at       END,
    driver_arrived_at   = CASE WHEN p_new_status = 'driver_arrived'  THEN NOW() ELSE driver_arrived_at END,
    started_at          = CASE WHEN p_new_status = 'ride_started'    THEN NOW() ELSE started_at        END,
    completed_at        = CASE WHEN p_new_status = 'ride_completed'  THEN NOW() ELSE completed_at      END,
    -- Clear waiting fee the instant the driver resumes so it never accumulates past this point.
    waiting_started_at  = CASE
                            WHEN p_new_status = 'ride_started' AND v_ride.ride_status = 'ride_paused' THEN NULL
                            ELSE waiting_started_at
                          END,
    waiting_fee_per_min = CASE
                            WHEN p_new_status = 'ride_started' AND v_ride.ride_status = 'ride_paused' THEN NULL
                            ELSE waiting_fee_per_min
                          END,
    pause_reason        = CASE
                            WHEN p_new_status = 'ride_paused'  THEN p_pause_reason
                            WHEN p_new_status = 'ride_started' THEN NULL
                            ELSE pause_reason
                          END,
    cancelled_by        = CASE
                            WHEN p_new_status = 'cancelled' AND v_is_customer THEN 'customer'
                            WHEN p_new_status = 'cancelled' AND v_is_driver   THEN 'driver'
                            WHEN p_new_status = 'cancelled' AND v_is_admin    THEN 'admin'
                            ELSE cancelled_by
                          END,
    cancellation_fee    = CASE
                            WHEN p_new_status = 'cancelled' AND v_is_customer
                                 AND v_ride.ride_status = ANY(ARRAY['driver_assigned','driver_arriving','driver_arrived','ride_started','ride_paused'])
                            THEN ROUND((
                              COALESCE(v_ride.estimated_fare, 0) * 0.5
                              + COALESCE(v_waiting_mins, 0) * COALESCE(v_ride.waiting_fee_per_min, 75.0)
                            )::NUMERIC, 2)
                            ELSE cancellation_fee
                          END
  WHERE id = p_ride_id;

  IF p_latitude IS NOT NULL AND p_longitude IS NOT NULL THEN
    INSERT INTO ride_locations (ride_id, driver_id, lat, lng)
    VALUES (p_ride_id, v_ride.driver_id, p_latitude, p_longitude);
  END IF;

  RETURN jsonb_build_object('message', 'Ride status updated', 'new_status', p_new_status);
END;
$$;

GRANT EXECUTE ON FUNCTION update_ride_status TO authenticated;
