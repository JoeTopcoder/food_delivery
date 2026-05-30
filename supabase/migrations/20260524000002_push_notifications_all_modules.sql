-- Migration: Push notifications for Rides, Car Services, and Food Orders
-- Pattern: DB trigger → INSERT into notifications → existing trg_notification_push_fcm
-- fires and delivers FCM push to the user's device.
-- For driver direct-push (no notifications row needed), we call send-fcm-notification directly.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Fix send_fcm_on_notification_insert to forward full data JSONB
--    Previously only sent order_id; now merges NEW.data so ride_id /
--    booking_id / etc. reach the device automatically.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.send_fcm_on_notification_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _fcm_token    text;
  _edge_url     text := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/send-fcm-notification';
  _anon_key     text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InloYXJ3ZWxpcnVlbWpleG11dXhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0NDA1MTgsImV4cCI6MjA5MTAxNjUxOH0.etw9lBCZtWaJHPOiY6ozfFDEIMYcPQwG4hAah9whooA';
  _push_data    jsonb;
BEGIN
  SELECT fcm_token INTO _fcm_token
  FROM public.users
  WHERE id = NEW.user_id;

  IF _fcm_token IS NULL OR _fcm_token = '' THEN
    RETURN NEW;
  END IF;

  -- Build base data, then merge extra fields (ride_id, booking_id, …)
  _push_data := jsonb_build_object(
    'type',            NEW.type,
    'notification_id', NEW.id::text,
    'order_id',        COALESCE(NEW.order_id::text, '')
  );
  IF NEW.data IS NOT NULL THEN
    _push_data := _push_data || NEW.data;
  END IF;

  -- body must be jsonb (NOT ::text) — pg_net requirement
  PERFORM net.http_post(
    url     := _edge_url,
    body    := jsonb_build_object(
      'token', _fcm_token,
      'title', NEW.title,
      'body',  COALESCE(NEW.body, ''),
      'data',  _push_data
    ),
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || _anon_key
    )
  );

  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. RIDE — customer notified when ride is first placed
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_customer_on_ride_placed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.scheduled_for IS NOT NULL THEN
    INSERT INTO public.notifications (user_id, type, title, body, data, is_read, created_at)
    VALUES (
      NEW.customer_id,
      'ride_scheduled',
      '📅 Ride Scheduled!',
      'Your ride has been scheduled for ' ||
        TO_CHAR(NEW.scheduled_for AT TIME ZONE 'America/Jamaica', 'Mon DD "at" HH12:MI AM') || '.',
      jsonb_build_object('type', 'ride_scheduled', 'ride_id', NEW.id::text),
      FALSE, NOW()
    );
  ELSE
    INSERT INTO public.notifications (user_id, type, title, body, data, is_read, created_at)
    VALUES (
      NEW.customer_id,
      'ride_requested',
      '🚗 Ride Requested!',
      'Looking for a nearby driver. We''ll let you know as soon as one is found!',
      jsonb_build_object('type', 'ride_requested', 'ride_id', NEW.id::text),
      FALSE, NOW()
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ride_placed_customer_notify ON public.ride_requests;
CREATE TRIGGER trg_ride_placed_customer_notify
  AFTER INSERT ON public.ride_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_customer_on_ride_placed();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. RIDE — customer notified on every status change
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_customer_on_ride_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _title TEXT;
  _body  TEXT;
  _type  TEXT;
  _short TEXT;
BEGIN
  IF OLD.ride_status IS NOT DISTINCT FROM NEW.ride_status THEN
    RETURN NEW;
  END IF;

  _short := '#' || UPPER(SUBSTRING(NEW.id::text, 1, 6));

  CASE NEW.ride_status
    WHEN 'accepted' THEN
      _type  := 'ride_accepted';
      _title := '🚕 Driver Found!';
      _body  := 'Your ride ' || _short || ' has been accepted. Your driver is on the way to pick you up.';

    WHEN 'driver_arrived' THEN
      _type  := 'ride_driver_arrived';
      _title := '📍 Driver Arrived';
      _body  := 'Your driver has arrived at the pickup location for ride ' || _short || '.';

    WHEN 'in_progress' THEN
      _type  := 'ride_started';
      _title := '🚗 Ride Started';
      _body  := 'Your ride ' || _short || ' is now in progress. Enjoy the trip!';

    WHEN 'completed' THEN
      _type  := 'ride_completed';
      _title := '🎉 Ride Complete!';
      _body  := 'Your ride ' || _short || ' is complete. Thanks for riding with 7Dash!';

    WHEN 'cancelled' THEN
      _type  := 'ride_cancelled';
      _title := '❌ Ride Cancelled';
      _body  := 'Your ride ' || _short || ' has been cancelled.' ||
                CASE WHEN NEW.cancellation_reason IS NOT NULL AND NEW.cancellation_reason != ''
                     THEN ' Reason: ' || NEW.cancellation_reason ELSE '' END;

    ELSE
      RETURN NEW;
  END CASE;

  INSERT INTO public.notifications (user_id, type, title, body, data, is_read, created_at)
  VALUES (
    NEW.customer_id,
    _type, _title, _body,
    jsonb_build_object('type', _type, 'ride_id', NEW.id::text, 'ride_status', NEW.ride_status),
    FALSE, NOW()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ride_status_customer_notify ON public.ride_requests;
CREATE TRIGGER trg_ride_status_customer_notify
  AFTER UPDATE OF ride_status ON public.ride_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_customer_on_ride_status_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. RIDE — driver notified directly via FCM when a new offer arrives
--    (inserts into ride_driver_requests with status='offered')
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_driver_on_ride_offer()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _fcm_token    text;
  _supabase_url text := current_setting('app.settings.supabase_url', true);
  _service_key  text := current_setting('app.settings.service_role_key', true);
  _edge_url     text;
  _ride         RECORD;
BEGIN
  IF NEW.status != 'offered' THEN
    RETURN NEW;
  END IF;

  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';

  SELECT fcm_token INTO _fcm_token
  FROM public.users WHERE id = NEW.driver_id;

  IF _fcm_token IS NULL OR _fcm_token = '' THEN
    RETURN NEW;
  END IF;

  SELECT pickup_address, destination_address, estimated_fare, scheduled_for, is_airport_pickup, is_airport_dropoff
  INTO _ride
  FROM public.ride_requests WHERE id = NEW.ride_id;

  BEGIN
    PERFORM net.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'token', _fcm_token,
        'title', CASE
                   WHEN _ride.is_airport_pickup OR _ride.is_airport_dropoff THEN '✈️ Airport Ride Request!'
                   WHEN _ride.scheduled_for IS NOT NULL THEN '📅 Scheduled Ride Request'
                   ELSE '🔔 New Ride Request!'
                 END,
        'body',  COALESCE(_ride.pickup_address, 'Pickup') ||
                 ' → ' || COALESCE(_ride.destination_address, 'Destination') ||
                 '  •  J$' || ROUND(COALESCE(_ride.estimated_fare, 0))::text,
        'data',  jsonb_build_object(
          'type',              'new_ride_offer',
          'ride_id',           NEW.ride_id::text,
          'driver_request_id', NEW.id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || COALESCE(_service_key, '')
      )::jsonb
    );
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ride_offer_driver_notify ON public.ride_driver_requests;
CREATE TRIGGER trg_ride_offer_driver_notify
  AFTER INSERT ON public.ride_driver_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_driver_on_ride_offer();

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. CAR SERVICE — customer notified when booking is placed
--    + provider notified directly via FCM
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_on_car_service_booking_placed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _fcm_token    text;
  _supabase_url text := current_setting('app.settings.supabase_url', true);
  _service_key  text := current_setting('app.settings.service_role_key', true);
  _edge_url     text;
  _short        text;
BEGIN
  _short := '#' || COALESCE(UPPER(SUBSTRING(NEW.booking_number, 1, 8)), UPPER(SUBSTRING(NEW.id::text, 1, 8)));

  -- Customer: booking placed confirmation
  INSERT INTO public.notifications (user_id, type, title, body, data, is_read, created_at)
  VALUES (
    NEW.customer_id,
    'car_service_placed',
    '🚗 Booking Placed!',
    'Your car service booking ' || _short || ' is awaiting provider confirmation.',
    jsonb_build_object('type', 'car_service_placed', 'booking_id', NEW.id::text, 'booking_number', NEW.booking_number),
    FALSE, NOW()
  );

  -- Provider: direct FCM push
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';

  SELECT fcm_token INTO _fcm_token
  FROM public.users WHERE id = NEW.provider_id;

  IF _fcm_token IS NOT NULL AND _fcm_token != '' THEN
    BEGIN
      PERFORM net.http_post(
        url     := _edge_url,
        body    := jsonb_build_object(
          'token', _fcm_token,
          'title', '🔔 New Car Service Booking!',
          'body',  'Booking ' || _short || ' — ' ||
                   COALESCE(NEW.vehicle_make, '') || ' ' || COALESCE(NEW.vehicle_model, '') ||
                   CASE WHEN NEW.service_address IS NOT NULL AND NEW.service_address != ''
                        THEN ' at ' || NEW.service_address ELSE '' END || '.',
          'data',  jsonb_build_object(
            'type',           'new_car_service_booking',
            'booking_id',     NEW.id::text,
            'booking_number', NEW.booking_number
          )
        )::text,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || COALESCE(_service_key, '')
        )::jsonb
      );
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_car_service_placed_notify ON public.car_service_bookings;
CREATE TRIGGER trg_car_service_placed_notify
  AFTER INSERT ON public.car_service_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_car_service_booking_placed();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. CAR SERVICE — customer notified on every status change
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_on_car_service_status_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _title     TEXT;
  _body      TEXT;
  _type      TEXT;
  _short     TEXT;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  _short := '#' || COALESCE(UPPER(SUBSTRING(NEW.booking_number, 1, 8)), UPPER(SUBSTRING(NEW.id::text, 1, 8)));

  CASE NEW.status
    WHEN 'confirmed' THEN
      _type  := 'car_service_confirmed';
      _title := '✅ Booking Confirmed!';
      _body  := 'Your car service booking ' || _short || ' has been confirmed. See you at the scheduled time!';

    WHEN 'on_the_way' THEN
      _type  := 'car_service_on_the_way';
      _title := '🚗 Provider On The Way!';
      _body  := 'Your service provider is heading to you for booking ' || _short || '.';

    WHEN 'in_progress' THEN
      _type  := 'car_service_started';
      _title := '🔧 Service In Progress';
      _body  := 'Your car service has started for booking ' || _short || '.';

    WHEN 'completed' THEN
      _type  := 'car_service_completed';
      _title := '✅ Service Complete!';
      _body  := 'Your car service booking ' || _short || ' is done. We hope you love the result!';

    WHEN 'cancelled' THEN
      _type  := 'car_service_cancelled';
      _title := '❌ Booking Cancelled';
      _body  := 'Your car service booking ' || _short || ' has been cancelled.' ||
                CASE WHEN NEW.cancellation_reason IS NOT NULL AND NEW.cancellation_reason != ''
                     THEN ' Reason: ' || NEW.cancellation_reason ELSE '' END;

    ELSE
      RETURN NEW;
  END CASE;

  INSERT INTO public.notifications (user_id, type, title, body, data, is_read, created_at)
  VALUES (
    NEW.customer_id,
    _type, _title, _body,
    jsonb_build_object('type', _type, 'booking_id', NEW.id::text, 'booking_number', NEW.booking_number, 'booking_status', NEW.status),
    FALSE, NOW()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_car_service_status_notify ON public.car_service_bookings;
CREATE TRIGGER trg_car_service_status_notify
  AFTER UPDATE OF status ON public.car_service_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_car_service_status_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. FOOD ORDERS — add missing 'ready' status notification
--    (pickup orders: "Your order is ready for collection")
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION notify_customer_on_order_status_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  _title TEXT;
  _body  TEXT;
  _type  TEXT;
BEGIN
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  CASE NEW.status
    WHEN 'confirmed' THEN
      _type  := 'order_confirmed';
      _title := '✅ Order Confirmed!';
      _body  := 'Your order #' || UPPER(SUBSTRING(NEW.id::text, 1, 8)) ||
                ' has been confirmed and is waiting to be prepared.';

    WHEN 'preparing' THEN
      _type  := 'preparing';
      _title := '👨‍🍳 Being Prepared';
      _body  := 'The restaurant is now preparing your order #' ||
                UPPER(SUBSTRING(NEW.id::text, 1, 8)) || '. Hang tight!';

    WHEN 'ready' THEN
      _type  := 'order_ready';
      _title := '🛎️ Order Ready!';
      _body  := CASE WHEN NEW.is_pickup IS TRUE
                     THEN 'Your order #' || UPPER(SUBSTRING(NEW.id::text, 1, 8)) || ' is ready for collection!'
                     ELSE 'Your order #' || UPPER(SUBSTRING(NEW.id::text, 1, 8)) || ' is ready and a driver is being assigned.'
                END;

    WHEN 'out_for_delivery' THEN
      _type  := 'out_for_delivery';
      _title := '🛵 Rider Assigned!';
      _body  := 'A rider has been assigned to your order #' ||
                UPPER(SUBSTRING(NEW.id::text, 1, 8)) || ' and is on the way to you.';

    WHEN 'delivered' THEN
      _type  := 'delivered';
      _title := '🎉 Order Delivered!';
      _body  := 'Your order #' || UPPER(SUBSTRING(NEW.id::text, 1, 8)) ||
                ' has been delivered. Thank you for using 7Dash!';

    WHEN 'cancelled' THEN
      _type  := 'order_cancelled';
      _title := '❌ Order Cancelled';
      _body  := 'Your order #' || UPPER(SUBSTRING(NEW.id::text, 1, 8)) ||
                ' has been cancelled. If you were charged, a refund is on its way.';

    ELSE
      RETURN NEW;
  END CASE;

  INSERT INTO public.notifications (
    user_id, order_id, type, title, body, data, is_read, created_at
  ) VALUES (
    NEW.user_id, NEW.id,
    _type, _title, _body,
    jsonb_build_object('order_id', NEW.id, 'status', NEW.status, 'type', _type),
    FALSE, NOW()
  );

  RETURN NEW;
END;
$$;
