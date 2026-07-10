-- Fix: lock_ledger_entries_for_payout now splits the last entry when it
-- overshoots the requested amount, so the remainder stays available.
--
-- Before: requesting $3 from a $4 entry would lock the full $4.
-- After:  the $4 entry is split into a locked $3 entry + a new available $1 entry.

CREATE OR REPLACE FUNCTION public.lock_ledger_entries_for_payout(
  p_user_id          uuid,
  p_role             text,
  p_amount_cents     bigint,
  p_payout_request_id uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_total_locked     bigint  := 0;
  v_entries_locked   integer := 0;
  v_entry            RECORD;
  v_still_need       bigint;
  v_split_amount     bigint;
BEGIN
  FOR v_entry IN
    SELECT id, amount_cents,
           user_id, role, order_id, ride_id, restaurant_id, driver_id,
           type, direction, currency, available_at, description, metadata
    FROM   earnings_ledger
    WHERE  user_id   = p_user_id
      AND  role      = p_role
      AND  status    = 'available'
      AND  direction = 'credit'
    ORDER BY created_at ASC
    FOR UPDATE SKIP LOCKED
  LOOP
    EXIT WHEN v_total_locked >= p_amount_cents;

    v_still_need := p_amount_cents - v_total_locked;

    IF v_entry.amount_cents <= v_still_need THEN
      -- Lock the full entry
      UPDATE earnings_ledger
      SET    status = 'locked',
             payout_request_id = p_payout_request_id,
             updated_at = now()
      WHERE  id = v_entry.id;

      INSERT INTO payout_request_ledger_entries
        (payout_request_id, ledger_entry_id, amount_cents)
      VALUES
        (p_payout_request_id, v_entry.id, v_entry.amount_cents)
      ON CONFLICT (ledger_entry_id) DO NOTHING;

      v_total_locked   := v_total_locked + v_entry.amount_cents;
      v_entries_locked := v_entries_locked + 1;

    ELSE
      -- Entry overshoots: lock only the needed portion, keep remainder available.
      v_split_amount := v_entry.amount_cents - v_still_need;

      -- Shrink the existing entry to just what's needed and lock it
      UPDATE earnings_ledger
      SET    amount_cents = v_still_need,
             status       = 'locked',
             payout_request_id = p_payout_request_id,
             updated_at   = now()
      WHERE  id = v_entry.id;

      INSERT INTO payout_request_ledger_entries
        (payout_request_id, ledger_entry_id, amount_cents)
      VALUES
        (p_payout_request_id, v_entry.id, v_still_need)
      ON CONFLICT (ledger_entry_id) DO NOTHING;

      -- Insert a new available entry for the remainder
      INSERT INTO earnings_ledger
        (user_id, role, order_id, ride_id, restaurant_id, driver_id,
         type, direction, amount_cents, currency, status, available_at,
         description, metadata)
      SELECT
        v_entry.user_id,   v_entry.role,
        v_entry.order_id,  v_entry.ride_id,
        v_entry.restaurant_id, v_entry.driver_id,
        v_entry.type,      v_entry.direction,
        v_split_amount,    v_entry.currency,
        'available',       v_entry.available_at,
        v_entry.description, v_entry.metadata;

      v_total_locked   := v_total_locked + v_still_need;
      v_entries_locked := v_entries_locked + 1;
    END IF;
  END LOOP;

  IF v_total_locked < p_amount_cents THEN
    RAISE EXCEPTION 'Insufficient available balance. Available: %, Required: %',
      v_total_locked, p_amount_cents;
  END IF;

  RETURN jsonb_build_object(
    'locked_cents',   v_total_locked,
    'entries_count',  v_entries_locked
  );
END;
$$;
