-- Fix generate_car_service_booking_number to not require pgcrypto.
-- Replaces gen_random_bytes() with md5(random()::text) which is always available.

CREATE OR REPLACE FUNCTION public.generate_car_service_booking_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_date_str  TEXT;
  v_suffix    TEXT;
  v_candidate TEXT;
  v_attempts  INT := 0;
BEGIN
  IF NEW.booking_number IS NOT NULL AND NEW.booking_number <> '' THEN
    RETURN NEW;
  END IF;

  v_date_str := TO_CHAR(NOW() AT TIME ZONE 'UTC', 'YYYYMMDD');

  LOOP
    -- 5-char uppercase hex suffix, no extensions required
    v_suffix := UPPER(SUBSTRING(MD5(RANDOM()::text || CLOCK_TIMESTAMP()::text), 1, 5));
    v_candidate := 'CS-' || v_date_str || '-' || v_suffix;

    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.car_service_bookings
      WHERE booking_number = v_candidate
    );

    v_attempts := v_attempts + 1;
    IF v_attempts > 10 THEN
      v_candidate := 'CS-' || v_date_str || '-' || LPAD(
        (EXTRACT(MICROSECONDS FROM clock_timestamp())::BIGINT % 100000)::TEXT,
        5, '0'
      );
      EXIT;
    END IF;
  END LOOP;

  NEW.booking_number := v_candidate;
  RETURN NEW;
END;
$$;
