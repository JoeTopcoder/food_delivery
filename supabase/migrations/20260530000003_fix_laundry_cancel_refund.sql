-- Fix: release_laundry_reservation was reading reserved_amount AFTER the Dart
-- client had already zeroed it, so the refund amount was always 0 or just
-- pickup_fee. This migration:
--   1. Adds a fallback that reads from laundry_wallet_reservations when
--      reserved_amount is 0 (covers already-stuck bookings).
--   2. Marks laundry_wallet_reservations rows as 'released' on cancel.
--   3. Backfills refunds for existing cancelled bookings that were never refunded.

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
  v_customer_id  UUID;
  v_reserved_amt NUMERIC;
  v_pickup_fee   NUMERIC;
  v_refund       NUMERIC;
  v_cur_reserved NUMERIC;
  v_from_reserve NUMERIC;
  v_to_balance   NUMERIC;
BEGIN
  -- Read booking amounts
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

  -- Fallback: if reserved_amount was already zeroed by the client before this
  -- RPC ran, read the true total from laundry_wallet_reservations.
  IF v_reserved_amt = 0 THEN
    SELECT COALESCE(SUM(reserved_amount), 0)
    INTO v_reserved_amt
    FROM laundry_wallet_reservations
    WHERE booking_id = p_booking_id AND status = 'reserved';
  END IF;

  v_refund := GREATEST(v_reserved_amt, v_pickup_fee) - COALESCE(p_cancellation_fee, 0);

  IF v_refund <= 0 THEN
    RAISE NOTICE 'release_laundry_reservation: nothing to refund for booking %', p_booking_id;
    -- Still mark reservations released so the table stays consistent
    UPDATE laundry_wallet_reservations
    SET status = 'released', updated_at = NOW()
    WHERE booking_id = p_booking_id AND status = 'reserved';
    RETURN;
  END IF;

  -- Read current wallet state
  SELECT COALESCE(reserved_balance, 0)
  INTO v_cur_reserved
  FROM wallets
  WHERE user_id = v_customer_id;

  -- Release from reserved_balance first; credit any remainder to balance
  v_from_reserve := LEAST(v_cur_reserved, v_refund);
  v_to_balance   := v_refund - v_from_reserve;

  UPDATE wallets SET
    reserved_balance = GREATEST(0, reserved_balance - v_from_reserve),
    balance          = balance + v_to_balance,
    updated_at       = NOW()
  WHERE user_id = v_customer_id;

  -- Record refund transaction (skip if one already exists for this booking)
  INSERT INTO wallet_transactions (user_id, amount, type, status, description, order_id)
  SELECT v_customer_id, v_refund, 'refund', 'completed',
         'Laundry booking cancelled — ' || p_reason, p_booking_id
  WHERE NOT EXISTS (
    SELECT 1 FROM wallet_transactions
    WHERE order_id = p_booking_id AND type = 'refund'
  );

  -- Mark component reservations as released
  UPDATE laundry_wallet_reservations
  SET status = 'released', updated_at = NOW()
  WHERE booking_id = p_booking_id AND status = 'reserved';

  -- Zero out the booking reservation
  UPDATE laundry_bookings
  SET reserved_amount = 0
  WHERE id = p_booking_id;

  RAISE NOTICE 'release_laundry_reservation: refunded % to % (from_reserve=%, to_balance=%)',
    v_refund, v_customer_id, v_from_reserve, v_to_balance;
END;
$$;

GRANT EXECUTE ON FUNCTION release_laundry_reservation(UUID, TEXT, NUMERIC) TO authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Backfill: refund any existing cancelled bookings that still have funds stuck
-- in reserved_balance (i.e. no refund transaction was recorded).
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
DECLARE
  r RECORD;
  v_reserved_amt NUMERIC;
  v_cur_reserved NUMERIC;
  v_from_reserve NUMERIC;
  v_to_balance   NUMERIC;
BEGIN
  FOR r IN
    SELECT lb.id AS booking_id,
           lb.customer_id,
           COALESCE(lb.reserved_amount, 0) AS reserved_amount,
           COALESCE(lb.pickup_fee, 0)      AS pickup_fee
    FROM laundry_bookings lb
    WHERE lb.status = 'cancelled'
      AND NOT EXISTS (
        SELECT 1 FROM wallet_transactions wt
        WHERE wt.order_id = lb.id AND wt.type = 'refund'
      )
  LOOP
    -- Prefer reserved_amount; fallback to reservations table
    v_reserved_amt := r.reserved_amount;
    IF v_reserved_amt = 0 THEN
      SELECT COALESCE(SUM(reserved_amount), 0)
      INTO v_reserved_amt
      FROM laundry_wallet_reservations
      WHERE booking_id = r.booking_id AND status = 'reserved';
    END IF;

    -- Final fallback: pickup_fee
    IF v_reserved_amt = 0 THEN
      v_reserved_amt := r.pickup_fee;
    END IF;

    CONTINUE WHEN v_reserved_amt <= 0;

    SELECT COALESCE(reserved_balance, 0)
    INTO v_cur_reserved
    FROM wallets WHERE user_id = r.customer_id;

    v_from_reserve := LEAST(v_cur_reserved, v_reserved_amt);
    v_to_balance   := v_reserved_amt - v_from_reserve;

    UPDATE wallets SET
      reserved_balance = GREATEST(0, reserved_balance - v_from_reserve),
      balance          = balance + v_to_balance,
      updated_at       = NOW()
    WHERE user_id = r.customer_id;

    INSERT INTO wallet_transactions (user_id, amount, type, status, description, order_id)
    VALUES (r.customer_id, v_reserved_amt, 'refund', 'completed',
            'Laundry booking cancelled — backfill refund', r.booking_id);

    UPDATE laundry_wallet_reservations
    SET status = 'released', updated_at = NOW()
    WHERE booking_id = r.booking_id AND status = 'reserved';

    UPDATE laundry_bookings SET reserved_amount = 0 WHERE id = r.booking_id;

    RAISE NOTICE 'Backfill: refunded % to % for booking %',
      v_reserved_amt, r.customer_id, r.booking_id;
  END LOOP;
END $$;
