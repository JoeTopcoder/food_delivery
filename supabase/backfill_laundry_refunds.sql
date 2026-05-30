-- Backfill: refund all cancelled laundry bookings that never got a refund transaction.
-- Safe to run multiple times (idempotent — skips bookings that already have a refund record).
-- Note: wallet_transactions.order_id FK references orders, not laundry_bookings,
--       so we store NULL for order_id and embed the booking ID in the description.

DO $$
DECLARE
  r              RECORD;
  v_reserved_amt NUMERIC;
  v_cur_reserved NUMERIC;
  v_from_reserve NUMERIC;
  v_to_balance   NUMERIC;
  v_count        INTEGER := 0;
BEGIN
  FOR r IN
    SELECT lb.id          AS booking_id,
           lb.customer_id,
           COALESCE(lb.reserved_amount, 0) AS reserved_amount,
           COALESCE(lb.pickup_fee,      0) AS pickup_fee
    FROM laundry_bookings lb
    WHERE lb.status = 'cancelled'
      AND NOT EXISTS (
        SELECT 1 FROM wallet_transactions wt
        WHERE wt.user_id = lb.customer_id
          AND wt.type = 'refund'
          AND wt.description LIKE '%' || lb.id::text || '%'
      )
  LOOP
    -- 1. Prefer reserved_amount on the booking
    v_reserved_amt := r.reserved_amount;

    -- 2. Fallback: sum of still-reserved rows in laundry_wallet_reservations
    IF v_reserved_amt = 0 THEN
      SELECT COALESCE(SUM(lwr.reserved_amount), 0)
      INTO v_reserved_amt
      FROM laundry_wallet_reservations lwr
      WHERE lwr.booking_id = r.booking_id AND lwr.status = 'reserved';
    END IF;

    -- 3. Last resort: at least return the pickup fee
    IF v_reserved_amt = 0 THEN
      v_reserved_amt := r.pickup_fee;
    END IF;

    CONTINUE WHEN v_reserved_amt <= 0;

    -- Read current wallet
    SELECT COALESCE(reserved_balance, 0)
    INTO v_cur_reserved
    FROM wallets
    WHERE user_id = r.customer_id;

    -- Release reserved_balance first; credit remainder to balance
    v_from_reserve := LEAST(v_cur_reserved, v_reserved_amt);
    v_to_balance   := v_reserved_amt - v_from_reserve;

    UPDATE wallets SET
      reserved_balance = GREATEST(0, reserved_balance - v_from_reserve),
      balance          = balance + v_to_balance,
      updated_at       = NOW()
    WHERE user_id = r.customer_id;

    -- Record refund (order_id NULL because FK references orders, not laundry_bookings;
    -- booking ID is embedded in description for traceability)
    INSERT INTO wallet_transactions (user_id, amount, type, status, description, order_id)
    VALUES (
      r.customer_id,
      v_reserved_amt,
      'refund',
      'completed',
      'Laundry booking cancelled — backfill refund [laundry:' || r.booking_id::text || ']',
      NULL
    );

    -- Mark component reservations as released
    UPDATE laundry_wallet_reservations
    SET status     = 'released',
        updated_at = NOW()
    WHERE booking_id = r.booking_id AND status = 'reserved';

    -- Zero out reservation on booking
    UPDATE laundry_bookings
    SET reserved_amount = 0
    WHERE id = r.booking_id;

    v_count := v_count + 1;
    RAISE NOTICE 'Refunded % to customer % for booking % (from_reserve=%, to_balance=%)',
      v_reserved_amt, r.customer_id, r.booking_id, v_from_reserve, v_to_balance;
  END LOOP;

  RAISE NOTICE 'Backfill complete: % booking(s) refunded', v_count;
END $$;
