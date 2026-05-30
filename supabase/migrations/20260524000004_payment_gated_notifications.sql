-- Payment-gated placement notifications for Rides and Car Service.
-- Grocery/Food already handled by migration 20260524000003 (same orders table).
--
-- Rules:
--   Cash bookings  → notify immediately on INSERT (no gateway involved)
--   Card/Wallet    → notify when payment_status transitions to 'authorized' or 'paid'

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. RIDES — notify customer only after payment confirmed
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_customer_on_ride_placed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- INSERT path: cash only (card/wallet wait for payment webhook)
  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.payment_method, 'card') != 'cash' THEN
      RETURN NEW;
    END IF;
  END IF;

  -- UPDATE path: fire only when payment_status just became authorized or paid
  IF TG_OP = 'UPDATE' THEN
    IF NOT (
      NEW.payment_status IN ('authorized', 'paid')
      AND OLD.payment_status IS DISTINCT FROM NEW.payment_status
      AND OLD.payment_status NOT IN ('authorized', 'paid')
    ) THEN
      RETURN NEW;
    END IF;
  END IF;

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
      'Your booking is confirmed. Looking for a nearby driver!',
      jsonb_build_object('type', 'ride_requested', 'ride_id', NEW.id::text),
      FALSE, NOW()
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ride_placed_customer_notify ON public.ride_requests;
CREATE TRIGGER trg_ride_placed_customer_notify
  AFTER INSERT OR UPDATE OF payment_status ON public.ride_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_customer_on_ride_placed();

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. CAR SERVICE — notify customer only after payment confirmed
--    Also fixes the ::text body cast bug in the provider FCM push.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_on_car_service_booking_placed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _short        TEXT;
  _fcm_token    text;
  _anon_key     text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InloYXJ3ZWxpcnVlbWpleG11dXhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0NDA1MTgsImV4cCI6MjA5MTAxNjUxOH0.etw9lBCZtWaJHPOiY6ozfFDEIMYcPQwG4hAah9whooA';
  _edge_url     text := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/send-fcm-notification';
BEGIN
  -- INSERT path: cash/wallet only (card waits for payment webhook)
  IF TG_OP = 'INSERT' THEN
    IF COALESCE(NEW.payment_method, 'card') = 'card' THEN
      RETURN NEW;
    END IF;
  END IF;

  -- UPDATE path: fire only when payment_status just became 'paid' or 'authorized'
  IF TG_OP = 'UPDATE' THEN
    IF NOT (
      NEW.payment_status IN ('authorized', 'paid')
      AND OLD.payment_status IS DISTINCT FROM NEW.payment_status
      AND OLD.payment_status NOT IN ('authorized', 'paid')
    ) THEN
      RETURN NEW;
    END IF;
  END IF;

  _short := '#' || COALESCE(UPPER(SUBSTRING(NEW.booking_number, 1, 8)), UPPER(SUBSTRING(NEW.id::text, 1, 8)));

  -- Customer notification
  INSERT INTO public.notifications (user_id, type, title, body, data, is_read, created_at)
  VALUES (
    NEW.customer_id,
    'car_service_placed',
    '🚗 Booking Confirmed!',
    'Your car service booking ' || _short || ' is confirmed and awaiting provider assignment.',
    jsonb_build_object('type', 'car_service_placed', 'booking_id', NEW.id::text, 'booking_number', NEW.booking_number),
    FALSE, NOW()
  );

  -- Provider: direct FCM push (body must be jsonb, not ::text)
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
        ),
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', 'Bearer ' || _anon_key
        )
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
  AFTER INSERT OR UPDATE OF payment_status ON public.car_service_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_on_car_service_booking_placed();
