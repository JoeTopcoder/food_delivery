-- Food commission in the platform commission tab must also include the
-- platform's share of the delivery fee (1 - driver_pay_percent), matching
-- get_financial_statistics.
CREATE OR REPLACE FUNCTION public.get_platform_commission_summary()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_food_total    NUMERIC := 0;
  v_food_month    NUMERIC := 0;
  v_laundry_total NUMERIC := 0;
  v_laundry_month NUMERIC := 0;
  v_car_total     NUMERIC := 0;
  v_car_month     NUMERIC := 0;
  v_ride_total    NUMERIC := 0;
  v_ride_month    NUMERIC := 0;
  v_month_start   TIMESTAMPTZ := date_trunc('month', NOW());
  v_driver_pct    NUMERIC := 0.80;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;

  SELECT COALESCE(NULLIF(value,'')::numeric, 0.80) INTO v_driver_pct
  FROM app_config WHERE key='driver_pay_percent';
  v_driver_pct := COALESCE(v_driver_pct, 0.80);

  -- Food & Grocery: restaurant commission + platform's delivery-fee share
  SELECT COALESCE(SUM(COALESCE(commission_amount,0) + COALESCE(delivery_fee,0) * (1 - v_driver_pct)), 0),
         COALESCE(SUM(CASE WHEN created_at >= v_month_start
              THEN COALESCE(commission_amount,0) + COALESCE(delivery_fee,0) * (1 - v_driver_pct) ELSE 0 END), 0)
  INTO v_food_total, v_food_month
  FROM orders
  WHERE status = 'delivered';

  SELECT COALESCE(SUM(platform_commission), 0),
         COALESCE(SUM(CASE WHEN created_at >= v_month_start THEN platform_commission ELSE 0 END), 0)
  INTO v_laundry_total, v_laundry_month
  FROM laundry_payment_splits WHERE status = 'settled';

  SELECT COALESCE(SUM(platform_fee), 0),
         COALESCE(SUM(CASE WHEN completed_at >= v_month_start THEN platform_fee END), 0)
  INTO v_car_total, v_car_month
  FROM car_service_bookings WHERE status = 'completed' AND platform_fee IS NOT NULL;

  SELECT COALESCE(SUM(platform_fee), 0),
         COALESCE(SUM(CASE WHEN updated_at >= v_month_start THEN platform_fee END), 0)
  INTO v_ride_total, v_ride_month
  FROM ride_requests WHERE ride_status = 'ride_completed' AND platform_fee IS NOT NULL;

  RETURN jsonb_build_object(
    'food',    jsonb_build_object('total', v_food_total,    'month', v_food_month),
    'laundry', jsonb_build_object('total', v_laundry_total, 'month', v_laundry_month),
    'car',     jsonb_build_object('total', v_car_total,     'month', v_car_month),
    'rides',   jsonb_build_object('total', v_ride_total,    'month', v_ride_month),
    'grand_total', v_food_total + v_laundry_total + v_car_total + v_ride_total,
    'month_total', v_food_month + v_laundry_month + v_car_month + v_ride_month
  );
END;
$function$;
NOTIFY pgrst, 'reload schema';
