-- Fix get_admin_dashboard_summary: ride_requests uses ride_status not status.
-- Correct active-ride values from schema: driver_assigned, driver_arriving,
-- driver_arrived, ride_started.

CREATE OR REPLACE FUNCTION public.get_admin_dashboard_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total_users         int := 0;
  v_total_restaurants   int := 0;
  v_pending_restaurants int := 0;
  v_total_drivers       int := 0;
  v_pending_drivers     int := 0;
  v_total_orders        int := 0;
  v_delivered_orders    int := 0;
  v_active_orders       int := 0;
  v_total_revenue       numeric := 0;
  v_monthly_revenue     numeric := 0;
  v_total_laundry       int := 0;
  v_active_laundry      int := 0;
  v_total_car_services  int := 0;
  v_active_car_services int := 0;
  v_total_rides         int := 0;
  v_active_rides        int := 0;
  v_month_start         timestamptz;
BEGIN
  v_month_start := date_trunc('month', now());

  -- Users
  BEGIN
    SELECT COUNT(*) INTO v_total_users FROM public.users;
  EXCEPTION WHEN OTHERS THEN v_total_users := 0; END;

  -- Restaurants
  BEGIN
    SELECT COUNT(*) INTO v_total_restaurants FROM public.restaurants;
  EXCEPTION WHEN OTHERS THEN v_total_restaurants := 0; END;

  BEGIN
    SELECT COUNT(*) INTO v_pending_restaurants
    FROM public.restaurants
    WHERE is_verified = false
      AND COALESCE(status, '') != 'rejected';
  EXCEPTION WHEN OTHERS THEN v_pending_restaurants := 0; END;

  -- Drivers
  BEGIN
    SELECT COUNT(*) INTO v_total_drivers FROM public.drivers;
  EXCEPTION WHEN OTHERS THEN v_total_drivers := 0; END;

  BEGIN
    SELECT COUNT(*) INTO v_pending_drivers
    FROM public.drivers
    WHERE driver_status IN ('pending_review', 'under_review', 'draft');
  EXCEPTION WHEN OTHERS THEN v_pending_drivers := 0; END;

  -- Orders
  BEGIN
    SELECT COUNT(*) INTO v_total_orders FROM public.orders;
  EXCEPTION WHEN OTHERS THEN v_total_orders := 0; END;

  BEGIN
    SELECT COUNT(*) INTO v_delivered_orders
    FROM public.orders WHERE status = 'delivered';
  EXCEPTION WHEN OTHERS THEN v_delivered_orders := 0; END;

  BEGIN
    SELECT COUNT(*) INTO v_active_orders
    FROM public.orders
    WHERE status IN ('confirmed','preparing','ready','picked_up','out_for_delivery','on_the_way');
  EXCEPTION WHEN OTHERS THEN v_active_orders := 0; END;

  -- Revenue
  BEGIN
    SELECT COALESCE(SUM(total_amount), 0) INTO v_total_revenue
    FROM public.orders WHERE status = 'delivered';
  EXCEPTION WHEN OTHERS THEN v_total_revenue := 0; END;

  BEGIN
    SELECT COALESCE(SUM(total_amount), 0) INTO v_monthly_revenue
    FROM public.orders
    WHERE status = 'delivered'
      AND ordered_at >= v_month_start;
  EXCEPTION WHEN OTHERS THEN v_monthly_revenue := 0; END;

  -- Laundry
  BEGIN
    SELECT COUNT(*) INTO v_total_laundry FROM public.laundry_bookings;
  EXCEPTION WHEN OTHERS THEN v_total_laundry := 0; END;

  BEGIN
    SELECT COUNT(*) INTO v_active_laundry
    FROM public.laundry_bookings
    WHERE status IN ('confirmed','picked_up','in_progress','out_for_delivery');
  EXCEPTION WHEN OTHERS THEN v_active_laundry := 0; END;

  -- Car services
  BEGIN
    SELECT COUNT(*) INTO v_total_car_services FROM public.car_service_bookings;
  EXCEPTION WHEN OTHERS THEN v_total_car_services := 0; END;

  BEGIN
    SELECT COUNT(*) INTO v_active_car_services
    FROM public.car_service_bookings
    WHERE status IN ('confirmed','in_progress');
  EXCEPTION WHEN OTHERS THEN v_active_car_services := 0; END;

  -- Rides (ride_requests uses ride_status, not status)
  BEGIN
    SELECT COUNT(*) INTO v_total_rides FROM public.ride_requests;
  EXCEPTION WHEN OTHERS THEN v_total_rides := 0; END;

  BEGIN
    SELECT COUNT(*) INTO v_active_rides
    FROM public.ride_requests
    WHERE ride_status IN ('driver_assigned','driver_arriving','driver_arrived','ride_started');
  EXCEPTION WHEN OTHERS THEN v_active_rides := 0; END;

  RETURN jsonb_build_object(
    'users', jsonb_build_object(
      'total_users', v_total_users
    ),
    'restaurants', jsonb_build_object(
      'total_restaurants', v_total_restaurants,
      'pending',           v_pending_restaurants
    ),
    'drivers', jsonb_build_object(
      'total_drivers', v_total_drivers,
      'pending',       v_pending_drivers
    ),
    'orders', jsonb_build_object(
      'total_orders',     v_total_orders,
      'delivered_orders', v_delivered_orders,
      'active_orders',    v_active_orders,
      'completion_rate',  CASE
        WHEN v_total_orders > 0
        THEN round((v_delivered_orders::numeric / v_total_orders * 100), 1)
        ELSE 0
      END
    ),
    'revenue', jsonb_build_object(
      'total_revenue',   v_total_revenue,
      'monthly_revenue', v_monthly_revenue
    ),
    'laundry', jsonb_build_object(
      'total_bookings',  v_total_laundry,
      'active_bookings', v_active_laundry
    ),
    'car_services', jsonb_build_object(
      'total_bookings',  v_total_car_services,
      'active_bookings', v_active_car_services
    ),
    'rides', jsonb_build_object(
      'total_rides',  v_total_rides,
      'active_rides', v_active_rides
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_admin_dashboard_summary() TO authenticated;
