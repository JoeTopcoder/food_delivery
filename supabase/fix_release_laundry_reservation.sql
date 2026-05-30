CREATE OR REPLACE FUNCTION release_laundry_reservation(
  p_booking_id       UUID,
  p_reason           TEXT    DEFAULT 'cancelled',
  p_cancellation_fee NUMERIC DEFAULT 0
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id    UUID;
  v_reserved_amt   NUMERIC;
  v_pickup_fee     NUMERIC;
  v_refund         NUMERIC;
  v_cur_reserved   NUMERIC;
  v_from_reserve   NUMERIC;
  v_to_balance     NUMERIC;
  v_services       TEXT;
BEGIN
  SELECT customer_id,
         COALESCE(reserved_amount, 0),
         COALESCE(pickup_fee, 0)
  INTO v_customer_id, v_reserved_amt, v_pickup_fee
  FROM laundry_bookings
  WHERE id = p_booking_id;

  IF v_customer_id IS NULL THEN
    RAISE NOTICE 'release_laundry_reservation: booking % not found', p_booking_id;
    RETURN;
  END IF;

  -- Build a human-readable list of services booked
  SELECT COALESCE(string_agg(service_name, ', ' ORDER BY service_name), 'Laundry Service')
  INTO v_services
  FROM laundry_booking_items
  WHERE booking_id = p_booking_id;

  -- Fallback: if reserved_amount was already zeroed, read from reservations table
  IF v_reserved_amt = 0 THEN
    SELECT COALESCE(SUM(reserved_amount), 0)
    INTO v_reserved_amt
    FROM laundry_wallet_reservations
    WHERE booking_id = p_booking_id AND status = 'reserved';
  END IF;

  v_refund := GREATEST(v_reserved_amt, v_pickup_fee) - COALESCE(p_cancellation_fee, 0);

  IF v_refund <= 0 THEN
    RAISE NOTICE 'release_laundry_reservation: nothing to refund for booking %', p_booking_id;
    UPDATE laundry_wallet_reservations
      SET status = 'released', updated_at = NOW()
      WHERE booking_id = p_booking_id AND status = 'reserved';
    RETURN;
  END IF;

  SELECT COALESCE(reserved_balance, 0)
  INTO v_cur_reserved
  FROM wallets
  WHERE user_id = v_customer_id;

  v_from_reserve := LEAST(v_cur_reserved, v_refund);
  v_to_balance   := v_refund - v_from_reserve;

  UPDATE wallets SET
    reserved_balance = GREATEST(0, reserved_balance - v_from_reserve),
    balance          = balance + v_to_balance,
    updated_at       = NOW()
  WHERE user_id = v_customer_id;

  -- Description shows the actual services so customers know what was refunded.
  -- order_id is NULL because the FK references orders, not laundry_bookings.
  INSERT INTO wallet_transactions (user_id, amount, type, status, description, order_id)
  SELECT v_customer_id, v_refund, 'refund', 'completed',
         'Laundry cancelled: ' || v_services || ' — refunded to wallet',
         NULL
  WHERE NOT EXISTS (
    SELECT 1 FROM wallet_transactions
    WHERE user_id = v_customer_id
      AND type = 'refund'
      AND description LIKE '%' || p_booking_id::text || '%'
  );

  UPDATE laundry_wallet_reservations
    SET status = 'released', updated_at = NOW()
    WHERE booking_id = p_booking_id AND status = 'reserved';

  UPDATE laundry_bookings
    SET reserved_amount = 0
    WHERE id = p_booking_id;

  RAISE NOTICE 'release_laundry_reservation: refunded % to % for [%] (from_reserve=%, to_balance=%)',
    v_refund, v_customer_id, v_services, v_from_reserve, v_to_balance;
END;
$$;

GRANT EXECUTE ON FUNCTION release_laundry_reservation(UUID, TEXT, NUMERIC) TO authenticated;
