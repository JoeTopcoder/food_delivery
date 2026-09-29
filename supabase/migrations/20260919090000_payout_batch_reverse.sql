-- Make payout runs reversible: snapshot each affected entity's pre-run
-- total_paid_out / cash_float into payout_batch_items, and add
-- reverse_payout_batch() to restore them and delete the run. This captures
-- EVERY affected entity — paid drivers, paid restaurants, AND drivers whose
-- balance was only offset against their float (no payout) — so an undo is exact.

CREATE TABLE IF NOT EXISTS payout_batch_items (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id            uuid NOT NULL REFERENCES payout_batches(id) ON DELETE CASCADE,
  entity_type         text NOT NULL,
  entity_id           uuid NOT NULL,
  amount_paid         numeric NOT NULL DEFAULT 0,
  prev_total_paid_out numeric,
  prev_cash_float     numeric
);
ALTER TABLE payout_batch_items ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payout_batch_items_admin ON payout_batch_items;
CREATE POLICY payout_batch_items_admin ON payout_batch_items FOR SELECT
  USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'admin'));

CREATE OR REPLACE FUNCTION public.create_payout_batch()
RETURNS TABLE (
  entity_type         text,
  entity_name         text,
  bank_name           text,
  bank_branch         text,
  bank_account_number text,
  bank_account_holder text,
  bank_account_type   text,
  amount              numeric,
  batch_id            uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_batch uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_uid AND role = 'admin') THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  INSERT INTO payout_batches (created_by) VALUES (v_uid) RETURNING id INTO v_batch;

  -- Snapshot pre-run state of every entity this run will touch.
  -- Paid drivers (net = balance - float > 0, has bank).
  INSERT INTO payout_batch_items (batch_id, entity_type, entity_id, amount_paid,
    prev_total_paid_out, prev_cash_float)
  SELECT v_batch, 'driver', d.id,
         round((d.total_earnings - coalesce(d.total_paid_out,0) - coalesce(d.cash_float,0))::numeric,2),
         coalesce(d.total_paid_out,0), coalesce(d.cash_float,0)
  FROM drivers d
  WHERE d.user_id IS NOT NULL
    AND coalesce(trim(d.bank_account_number),'') <> ''
    AND (d.total_earnings - coalesce(d.total_paid_out,0) - coalesce(d.cash_float,0)) > 0.005;
  -- Offset-only drivers (still owe after applying balance; no payment).
  INSERT INTO payout_batch_items (batch_id, entity_type, entity_id, amount_paid,
    prev_total_paid_out, prev_cash_float)
  SELECT v_batch, 'driver', d.id, 0,
         coalesce(d.total_paid_out,0), coalesce(d.cash_float,0)
  FROM drivers d
  WHERE d.user_id IS NOT NULL
    AND (d.total_earnings - coalesce(d.total_paid_out,0)) > 0.005
    AND (d.total_earnings - coalesce(d.total_paid_out,0) - coalesce(d.cash_float,0)) <= 0.005;
  -- Paid restaurants.
  INSERT INTO payout_batch_items (batch_id, entity_type, entity_id, amount_paid,
    prev_total_paid_out, prev_cash_float)
  SELECT v_batch, 'restaurant', r.id,
         round((r.total_earnings - coalesce(r.total_paid_out,0))::numeric,2),
         coalesce(r.total_paid_out,0), NULL
  FROM restaurants r
  WHERE r.owner_id IS NOT NULL
    AND coalesce(trim(r.bank_account_number),'') <> ''
    AND (r.total_earnings - coalesce(r.total_paid_out,0)) > 0.005;

  -- 1) Pay net-positive drivers with bank info.
  INSERT INTO payout_requests (requester_id, requester_type, driver_id, amount,
    bank_name, bank_branch, bank_account_number, bank_account_holder,
    bank_account_type, status, batch_id, processed_at, admin_notes)
  SELECT d.user_id, 'driver', d.id,
         round((d.total_earnings - coalesce(d.total_paid_out,0) - coalesce(d.cash_float,0))::numeric,2),
         d.bank_name, d.bank_branch, d.bank_account_number, d.bank_account_holder,
         d.bank_account_type, 'completed', v_batch, now(),
         'Batch payout run (net of cash float)'
  FROM drivers d
  WHERE d.user_id IS NOT NULL
    AND coalesce(trim(d.bank_account_number),'') <> ''
    AND (d.total_earnings - coalesce(d.total_paid_out,0) - coalesce(d.cash_float,0)) > 0.005;

  UPDATE drivers d
    SET total_paid_out = d.total_earnings, cash_float = 0, updated_at = now()
  WHERE d.user_id IS NOT NULL
    AND coalesce(trim(d.bank_account_number),'') <> ''
    AND (d.total_earnings - coalesce(d.total_paid_out,0) - coalesce(d.cash_float,0)) > 0.005;

  -- 2) Offset net-negative drivers: balance -> 0, float -> float - balance.
  UPDATE drivers d
    SET cash_float = coalesce(d.cash_float,0) - (d.total_earnings - coalesce(d.total_paid_out,0)),
        total_paid_out = d.total_earnings,
        updated_at = now()
  WHERE d.user_id IS NOT NULL
    AND (d.total_earnings - coalesce(d.total_paid_out,0)) > 0.005
    AND (d.total_earnings - coalesce(d.total_paid_out,0) - coalesce(d.cash_float,0)) <= 0.005;

  -- 3) Restaurants.
  INSERT INTO payout_requests (requester_id, requester_type, restaurant_id, amount,
    bank_name, bank_branch, bank_account_number, bank_account_holder,
    bank_account_type, status, batch_id, processed_at, admin_notes)
  SELECT r.owner_id, 'restaurant', r.id,
         round((r.total_earnings - coalesce(r.total_paid_out,0))::numeric,2),
         r.bank_name, r.bank_branch, r.bank_account_number, r.bank_account_holder,
         r.bank_account_type, 'completed', v_batch, now(), 'Batch payout run'
  FROM restaurants r
  WHERE r.owner_id IS NOT NULL
    AND coalesce(trim(r.bank_account_number),'') <> ''
    AND (r.total_earnings - coalesce(r.total_paid_out,0)) > 0.005;

  UPDATE restaurants r SET total_paid_out = r.total_earnings, updated_at = now()
  WHERE r.owner_id IS NOT NULL
    AND coalesce(trim(r.bank_account_number),'') <> ''
    AND (r.total_earnings - coalesce(r.total_paid_out,0)) > 0.005;

  UPDATE payout_batches SET
    total_amount = (SELECT coalesce(sum(pr.amount),0) FROM payout_requests pr WHERE pr.batch_id = v_batch),
    item_count   = (SELECT count(*) FROM payout_requests pr WHERE pr.batch_id = v_batch)
  WHERE id = v_batch;

  RETURN QUERY
  SELECT pr.requester_type,
         CASE WHEN pr.requester_type = 'driver'
              THEN (SELECT full_name FROM drivers WHERE id = pr.driver_id)
              ELSE (SELECT name FROM restaurants WHERE id = pr.restaurant_id) END,
         pr.bank_name, pr.bank_branch, pr.bank_account_number,
         pr.bank_account_holder, pr.bank_account_type, pr.amount::numeric, pr.batch_id
  FROM payout_requests pr
  WHERE pr.batch_id = v_batch
  ORDER BY pr.requester_type, pr.amount DESC;
END;
$$;

-- Reverse a run: restore every touched entity's snapshot and delete the run.
-- With no argument, reverses the most recent batch.
CREATE OR REPLACE FUNCTION public.reverse_payout_batch(p_batch uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_batch uuid := p_batch;
  v_count integer;
  v_total numeric;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_uid AND role = 'admin') THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  IF v_batch IS NULL THEN
    SELECT id INTO v_batch FROM payout_batches ORDER BY created_at DESC LIMIT 1;
  END IF;
  IF v_batch IS NULL THEN
    RETURN jsonb_build_object('reversed', 0, 'total', 0);
  END IF;

  SELECT count(*), coalesce(sum(amount_paid),0)
    INTO v_count, v_total
  FROM payout_batch_items WHERE batch_id = v_batch;

  UPDATE drivers d SET
    total_paid_out = bi.prev_total_paid_out,
    cash_float     = bi.prev_cash_float,
    updated_at     = now()
  FROM payout_batch_items bi
  WHERE bi.batch_id = v_batch AND bi.entity_type = 'driver' AND d.id = bi.entity_id;

  UPDATE restaurants r SET
    total_paid_out = bi.prev_total_paid_out,
    updated_at     = now()
  FROM payout_batch_items bi
  WHERE bi.batch_id = v_batch AND bi.entity_type = 'restaurant' AND r.id = bi.entity_id;

  DELETE FROM payout_requests   WHERE batch_id = v_batch;
  DELETE FROM payout_batch_items WHERE batch_id = v_batch;
  DELETE FROM payout_batches     WHERE id = v_batch;

  RETURN jsonb_build_object('reversed', v_count, 'total', v_total);
END;
$$;

GRANT EXECUTE ON FUNCTION public.reverse_payout_batch(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
