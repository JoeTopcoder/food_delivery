-- Fix: cap waiting/pause fee at started_at in complete_ride_rpc.
-- Previously NOW() was used as the upper bound, causing the fee to keep
-- accumulating past the point where the driver resumed the ride.
-- started_at is updated to NOW() every time ride_started is set (initial
-- start AND resume from pause), so it is always the correct cap.

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
  v_fee_cap        TIMESTAMPTZ;
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

  -- Add waiting/pause fee, capped at started_at so it never accumulates
  -- past the point where the driver resumed the ride.
  IF v_ride.waiting_started_at IS NOT NULL AND v_ride.waiting_fee_per_min IS NOT NULL THEN
    v_fee_cap    := COALESCE(v_ride.started_at, NOW());
    v_waiting_mins := GREATEST(0,
      EXTRACT(EPOCH FROM (v_fee_cap - v_ride.waiting_started_at)) / 60
    );
    v_final_fare := v_final_fare + ROUND((v_waiting_mins * v_ride.waiting_fee_per_min)::NUMERIC, 2);
  END IF;

  v_final_fare     := ROUND(v_final_fare::NUMERIC, 2);
  v_platform_fee   := ROUND((v_final_fare * COALESCE(v_settings.platform_commission_percent, 20) / 100)::NUMERIC, 2);
  v_driver_earning := ROUND((v_final_fare - v_platform_fee)::NUMERIC, 2);

  v_payment_status := CASE
    WHEN v_ride.payment_method = 'cash'              THEN 'cash_pending'
    WHEN v_ride.payment_method IN ('card', 'wallet') THEN 'paid'
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
