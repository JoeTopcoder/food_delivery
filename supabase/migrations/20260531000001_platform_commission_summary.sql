-- Platform commission summary RPC for the admin unified earnings screen.
-- Returns total and monthly commissions broken down by service.

CREATE OR REPLACE FUNCTION get_platform_commission_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_food_total        NUMERIC := 0;
  v_food_month        NUMERIC := 0;
  v_laundry_total     NUMERIC := 0;
  v_laundry_month     NUMERIC := 0;
  v_car_total         NUMERIC := 0;
  v_car_month         NUMERIC := 0;
  v_ride_total        NUMERIC := 0;
  v_ride_month        NUMERIC := 0;
  v_month_start       TIMESTAMPTZ := date_trunc('month', NOW());
BEGIN
  -- Food & Grocery orders commission
  SELECT COALESCE(SUM(commission_amount), 0),
         COALESCE(SUM(CASE WHEN created_at >= v_month_start THEN commission_amount END), 0)
  INTO v_food_total, v_food_month
  FROM orders
  WHERE status = 'delivered' AND commission_amount IS NOT NULL;

  -- Laundry commission (query splits directly — avoids overcounting when joining
  -- the per-provider aggregated view against bookings with a LEFT JOIN)
  SELECT COALESCE(SUM(platform_commission), 0),
         COALESCE(SUM(CASE WHEN created_at >= v_month_start THEN platform_commission ELSE 0 END), 0)
  INTO v_laundry_total, v_laundry_month
  FROM laundry_payment_splits
  WHERE status = 'settled';

  -- Car services commission (platform_fee column on completed bookings)
  SELECT COALESCE(SUM(platform_fee), 0),
         COALESCE(SUM(CASE WHEN completed_at >= v_month_start THEN platform_fee END), 0)
  INTO v_car_total, v_car_month
  FROM car_service_bookings
  WHERE status = 'completed' AND platform_fee IS NOT NULL;

  -- Rides commission (platform_fee on completed rides)
  SELECT COALESCE(SUM(platform_fee), 0),
         COALESCE(SUM(CASE WHEN updated_at >= v_month_start THEN platform_fee END), 0)
  INTO v_ride_total, v_ride_month
  FROM ride_requests
  WHERE ride_status = 'ride_completed' AND platform_fee IS NOT NULL;

  RETURN jsonb_build_object(
    'food',    jsonb_build_object('total', v_food_total,    'month', v_food_month),
    'laundry', jsonb_build_object('total', v_laundry_total, 'month', v_laundry_month),
    'car',     jsonb_build_object('total', v_car_total,     'month', v_car_month),
    'rides',   jsonb_build_object('total', v_ride_total,    'month', v_ride_month),
    'grand_total',   v_food_total + v_laundry_total + v_car_total + v_ride_total,
    'month_total',   v_food_month + v_laundry_month + v_car_month + v_ride_month
  );
END;
$$;

GRANT EXECUTE ON FUNCTION get_platform_commission_summary() TO authenticated;
