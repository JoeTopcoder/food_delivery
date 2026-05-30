-- Backfill existing laundry refund transaction descriptions from:
--   "Laundry booking cancelled — backfill refund [laundry:UUID]"
-- to:
--   "Wash & Fold, Dry Cleaning · #LDY-0001 — refunded to wallet"

DO $$
DECLARE
  r              RECORD;
  v_booking_id   UUID;
  v_booking_num  TEXT;
  v_services     TEXT;
  v_new_desc     TEXT;
  v_count        INTEGER := 0;
BEGIN
  FOR r IN
    SELECT id, description
    FROM wallet_transactions
    WHERE type = 'refund'
      AND description LIKE '%[laundry:%'
  LOOP
    -- Extract UUID from "[laundry:UUID]"
    v_booking_id := (
      SELECT (regexp_match(r.description, '\[laundry:([a-f0-9\-]+)\]'))[1]::uuid
    );

    IF v_booking_id IS NULL THEN CONTINUE; END IF;

    -- Get booking number
    SELECT COALESCE(booking_number, v_booking_id::text)
    INTO v_booking_num
    FROM laundry_bookings
    WHERE id = v_booking_id;

    -- Get service names
    SELECT COALESCE(string_agg(service_name, ', ' ORDER BY service_name), 'Laundry Service')
    INTO v_services
    FROM laundry_booking_items
    WHERE booking_id = v_booking_id;

    v_new_desc := v_services || ' · ' || COALESCE(v_booking_num, v_booking_id::text) || ' — refunded to wallet';

    UPDATE wallet_transactions
    SET description = v_new_desc
    WHERE id = r.id;

    v_count := v_count + 1;
    RAISE NOTICE 'Updated tx %: %', r.id, v_new_desc;
  END LOOP;

  RAISE NOTICE 'Backfill complete: % transaction(s) updated', v_count;
END $$;
