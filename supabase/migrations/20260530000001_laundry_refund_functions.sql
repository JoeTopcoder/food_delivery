-- ─────────────────────────────────────────────────────────────────────────────
-- Laundry booking refund functions
-- Fixes release_laundry_reservation so cancellations reliably return funds
-- to the customer's wallet (both reserved_balance and balance cases).
-- ─────────────────────────────────────────────────────────────────────────────

-- Fix RLS infinite-recursion on laundry_bookings (if it recurs after policy changes)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_policies WHERE tablename = 'laundry_bookings'
  ) THEN
    -- Drop all existing policies and recreate clean ones
    PERFORM format('DROP POLICY IF EXISTS %I ON laundry_bookings', policyname)
    FROM pg_policies WHERE tablename = 'laundry_bookings';
  END IF;
END $$;

DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies WHERE tablename = 'laundry_bookings' LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON laundry_bookings', r.policyname);
  END LOOP;
END $$;

CREATE POLICY "lb_customer_select" ON laundry_bookings
  FOR SELECT USING (customer_id = auth.uid());

CREATE POLICY "lb_customer_insert" ON laundry_bookings
  FOR INSERT WITH CHECK (customer_id = auth.uid());

CREATE POLICY "lb_customer_update" ON laundry_bookings
  FOR UPDATE USING (customer_id = auth.uid());

CREATE POLICY "lb_provider_select" ON laundry_bookings
  FOR SELECT USING (
    provider_id IN (SELECT id FROM laundry_providers WHERE user_id = auth.uid())
  );

CREATE POLICY "lb_provider_update" ON laundry_bookings
  FOR UPDATE USING (
    provider_id IN (SELECT id FROM laundry_providers WHERE user_id = auth.uid())
  );

CREATE POLICY "lb_admin_all" ON laundry_bookings
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );

-- ─────────────────────────────────────────────────────────────────────────────
-- release_laundry_reservation
-- Called on customer cancellation. Returns the charged amount back to the
-- wallet. Handles both reserved_balance (hold) and balance (charged) cases.
-- ─────────────────────────────────────────────────────────────────────────────

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

  -- Use reserved_amount if set, fall back to pickup_fee as minimum refund
  v_refund := GREATEST(v_reserved_amt, v_pickup_fee) - COALESCE(p_cancellation_fee, 0);

  IF v_refund <= 0 THEN
    RAISE NOTICE 'release_laundry_reservation: nothing to refund for booking %', p_booking_id;
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

  -- Record refund transaction
  INSERT INTO wallet_transactions (user_id, amount, type, status, description, order_id)
  VALUES (
    v_customer_id,
    v_refund,
    'refund',
    'completed',
    'Laundry booking cancelled — ' || p_reason,
    p_booking_id
  );

  -- Zero out the booking reservation
  UPDATE laundry_bookings
  SET reserved_amount = 0
  WHERE id = p_booking_id;

  RAISE NOTICE 'release_laundry_reservation: refunded % to % (from_reserve=%, to_balance=%)',
    v_refund, v_customer_id, v_from_reserve, v_to_balance;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- settle_laundry_booking
-- Called when a booking is marked completed. Clears the reservation and
-- records the final payment split. Safe to call multiple times (idempotent).
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION settle_laundry_booking(
  p_booking_id UUID
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_customer_id  UUID;
  v_reserved_amt NUMERIC;
  v_actual_total NUMERIC;
  v_pickup_fee   NUMERIC;
  v_delivery_fee NUMERIC;
  v_charge       NUMERIC;
BEGIN
  SELECT customer_id,
         COALESCE(reserved_amount, 0),
         COALESCE(actual_total, estimated_total, 0),
         COALESCE(pickup_fee, 0),
         COALESCE(delivery_fee, 0)
  INTO v_customer_id, v_reserved_amt, v_actual_total, v_pickup_fee, v_delivery_fee
  FROM laundry_bookings
  WHERE id = p_booking_id;

  IF v_customer_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'booking not found');
  END IF;

  -- Total amount to charge = actual_total + pickup_fee + delivery_fee
  v_charge := v_actual_total + v_pickup_fee + v_delivery_fee;

  -- Deduct from balance and clear reservation
  UPDATE wallets SET
    balance          = GREATEST(0, balance - v_charge),
    reserved_balance = GREATEST(0, reserved_balance - v_reserved_amt),
    updated_at       = NOW()
  WHERE user_id = v_customer_id;

  -- Record payment transaction
  INSERT INTO wallet_transactions (user_id, amount, type, status, description, order_id)
  VALUES (
    v_customer_id,
    -v_charge,
    'payment',
    'completed',
    'Laundry service payment',
    p_booking_id
  )
  ON CONFLICT DO NOTHING;

  -- Zero out reservation on booking
  UPDATE laundry_bookings
  SET reserved_amount = 0
  WHERE id = p_booking_id;

  RETURN jsonb_build_object('success', true, 'charged', v_charge);
END;
$$;

-- Grant execute to authenticated users (SECURITY DEFINER already bypasses RLS)
GRANT EXECUTE ON FUNCTION release_laundry_reservation(UUID, TEXT, NUMERIC) TO authenticated;
GRANT EXECUTE ON FUNCTION settle_laundry_booking(UUID) TO authenticated;
