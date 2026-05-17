-- Postgres RPCs replacing the update-ride-status and complete-ride edge
-- functions. Called via supabase.rpc() (PostgREST) which accepts legacy JWTs
-- unlike edge-function JWT verification.

-- ============================================================
-- 1. update_ride_status
-- ============================================================
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

  -- Evaluate state-machine guard into a variable (avoids parser ambiguity)
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

  UPDATE ride_requests SET
    ride_status       = p_new_status,
    accepted_at       = CASE WHEN p_new_status = 'driver_arriving' THEN NOW() ELSE accepted_at       END,
    driver_arrived_at = CASE WHEN p_new_status = 'driver_arrived'  THEN NOW() ELSE driver_arrived_at END,
    started_at        = CASE WHEN p_new_status = 'ride_started'    THEN NOW() ELSE started_at        END,
    completed_at      = CASE WHEN p_new_status = 'ride_completed'  THEN NOW() ELSE completed_at      END,
    pause_reason      = CASE
                          WHEN p_new_status = 'ride_paused'  THEN p_pause_reason
                          WHEN p_new_status = 'ride_started' THEN NULL
                          ELSE pause_reason
                        END,
    cancelled_by      = CASE
                          WHEN p_new_status = 'cancelled' AND v_is_customer THEN 'customer'
                          WHEN p_new_status = 'cancelled' AND v_is_driver   THEN 'driver'
                          WHEN p_new_status = 'cancelled' AND v_is_admin    THEN 'admin'
                          ELSE cancelled_by
                        END,
    cancellation_fee  = CASE
                          WHEN p_new_status = 'cancelled'
                               AND v_is_customer
                               AND v_ride.ride_status = ANY(ARRAY['driver_assigned','driver_arriving','driver_arrived','ride_started'])
                          THEN ROUND((
                            COALESCE(v_ride.driver_earning, COALESCE(v_ride.estimated_fare, 0) * 0.8)
                            + CASE
                                WHEN v_ride.waiting_started_at IS NOT NULL
                                THEN GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_ride.waiting_started_at)) / 60)
                                     * COALESCE(v_ride.waiting_fee_per_min, 75.0)
                                ELSE 0
                              END
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


-- ============================================================
-- 2. complete_ride_rpc
-- ============================================================
CREATE OR REPLACE FUNCTION complete_ride_rpc(
  p_ride_id                UUID,
  p_final_distance_km      DOUBLE PRECISION DEFAULT NULL,
  p_final_duration_minutes DOUBLE PRECISION DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_user_id        UUID;
  v_ride           ride_requests%ROWTYPE;
  v_driver_id      UUID;
  v_settings       ride_pricing_settings%ROWTYPE;
  v_final_fare     NUMERIC;
  v_waiting_mins   NUMERIC;
  v_platform_fee   NUMERIC;
  v_driver_earning NUMERIC;
  v_payment_status TEXT;
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

  IF NOT (
    (v_ride.driver_id IS NOT NULL AND v_driver_id IS NOT NULL AND v_driver_id = v_ride.driver_id)
    OR EXISTS (SELECT 1 FROM users WHERE id = v_user_id AND role = 'admin')
  ) THEN
    RAISE EXCEPTION 'Only assigned driver or admin can complete ride';
  END IF;

  IF v_ride.ride_status NOT IN ('ride_started', 'ride_paused') THEN
    RAISE EXCEPTION 'Ride must be in ride_started or ride_paused status, current: %', v_ride.ride_status;
  END IF;

  SELECT * INTO v_settings FROM ride_pricing_settings WHERE active = true LIMIT 1;

  IF p_final_distance_km IS NOT NULL AND p_final_duration_minutes IS NOT NULL THEN
    v_final_fare := GREATEST(
      COALESCE(v_settings.minimum_fare, 5.0),
      (
        COALESCE(v_settings.base_fare, 3.0)
        + p_final_distance_km * COALESCE(v_settings.per_km_rate, 1.2)
        + p_final_duration_minutes * COALESCE(v_settings.per_minute_rate, 0.25)
      ) * COALESCE(v_settings.surge_multiplier, 1.0)
    );
  ELSE
    v_final_fare := COALESCE(v_ride.estimated_fare, 0);
  END IF;

  IF v_ride.waiting_started_at IS NOT NULL AND v_ride.waiting_fee_per_min IS NOT NULL THEN
    v_waiting_mins := GREATEST(0, EXTRACT(EPOCH FROM (NOW() - v_ride.waiting_started_at)) / 60);
    v_final_fare   := v_final_fare + ROUND((v_waiting_mins * v_ride.waiting_fee_per_min)::NUMERIC, 2);
  END IF;

  v_final_fare     := ROUND(v_final_fare::NUMERIC, 2);
  v_platform_fee   := ROUND((v_final_fare * COALESCE(v_settings.platform_commission_percent, 20) / 100)::NUMERIC, 2);
  v_driver_earning := ROUND((v_final_fare - v_platform_fee)::NUMERIC, 2);

  v_payment_status := CASE
    WHEN v_ride.payment_method = 'cash'                  THEN 'cash_pending'
    WHEN v_ride.payment_method IN ('card', 'wallet')     THEN 'paid'
    ELSE COALESCE(v_ride.payment_status, 'pending')
  END;

  UPDATE ride_requests SET
    ride_status    = 'ride_completed',
    final_fare     = v_final_fare,
    platform_fee   = v_platform_fee,
    driver_earning = v_driver_earning,
    payment_status = v_payment_status,
    completed_at   = NOW()
  WHERE id = p_ride_id;

  RETURN jsonb_build_object(
    'message',        'Ride completed successfully',
    'final_fare',     v_final_fare,
    'driver_earning', v_driver_earning,
    'platform_fee',   v_platform_fee,
    'payment_status', v_payment_status
  );
END;
$$;

GRANT EXECUTE ON FUNCTION complete_ride_rpc TO authenticated;
