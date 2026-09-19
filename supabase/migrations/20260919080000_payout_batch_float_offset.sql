-- Full float settlement in the payout run.
-- For each driver:  net = available balance - cash_float   (float>0 = driver owes)
--   net > 0  : we pay net; balance and float both settle to 0.
--   net <= 0 : we pay nothing, but the driver's earnings are still APPLIED to
--              their float debt — balance -> 0, float -> float - balance (the
--              remaining amount they still owe the company).
-- Restaurants have no float (paid on their balance).

-- Preview: drivers appear if they have earnings to settle OR we net-owe them.
-- `amount` is the NET (balance - float); negative means the driver still owes
-- that much after their balance is applied.
CREATE OR REPLACE FUNCTION public.preview_payout_batch()
RETURNS TABLE (
  entity_type         text,
  entity_name         text,
  bank_name           text,
  bank_branch         text,
  bank_account_number text,
  bank_account_holder text,
  bank_account_type   text,
  amount              numeric,
  has_bank            boolean
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT 'driver', d.full_name, d.bank_name, d.bank_branch,
         d.bank_account_number, d.bank_account_holder, d.bank_account_type,
         round((d.total_earnings - coalesce(d.total_paid_out,0)
                - coalesce(d.cash_float,0))::numeric, 2),
         coalesce(trim(d.bank_account_number),'') <> ''
  FROM drivers d
  WHERE d.user_id IS NOT NULL
    AND ((d.total_earnings - coalesce(d.total_paid_out,0)) > 0.005
         OR (d.total_earnings - coalesce(d.total_paid_out,0)
             - coalesce(d.cash_float,0)) > 0.005)
  UNION ALL
  SELECT 'restaurant', r.name, r.bank_name, r.bank_branch,
         r.bank_account_number, r.bank_account_holder, r.bank_account_type,
         round((r.total_earnings - coalesce(r.total_paid_out,0))::numeric, 2),
         coalesce(trim(r.bank_account_number),'') <> ''
  FROM restaurants r
  WHERE r.owner_id IS NOT NULL
    AND (r.total_earnings - coalesce(r.total_paid_out,0)) > 0.005
  ORDER BY 1, 8 DESC;
$$;

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

  -- 1) Pay net-positive drivers that have bank info (amount = balance - float).
  INSERT INTO payout_requests (requester_id, requester_type, driver_id, amount,
    bank_name, bank_branch, bank_account_number, bank_account_holder,
    bank_account_type, status, batch_id, processed_at, admin_notes)
  SELECT d.user_id, 'driver', d.id,
         round((d.total_earnings - coalesce(d.total_paid_out,0)
                - coalesce(d.cash_float,0))::numeric, 2),
         d.bank_name, d.bank_branch, d.bank_account_number, d.bank_account_holder,
         d.bank_account_type, 'completed', v_batch, now(),
         'Batch payout run (net of cash float)'
  FROM drivers d
  WHERE d.user_id IS NOT NULL
    AND coalesce(trim(d.bank_account_number),'') <> ''
    AND (d.total_earnings - coalesce(d.total_paid_out,0)
         - coalesce(d.cash_float,0)) > 0.005;

  UPDATE drivers d
    SET total_paid_out = d.total_earnings, cash_float = 0, updated_at = now()
  WHERE d.user_id IS NOT NULL
    AND coalesce(trim(d.bank_account_number),'') <> ''
    AND (d.total_earnings - coalesce(d.total_paid_out,0)
         - coalesce(d.cash_float,0)) > 0.005;

  -- 2) Net-negative drivers (still owe after applying their balance): no payment,
  --    but apply the balance against the float. balance -> 0, float -> float - balance.
  UPDATE drivers d
    SET cash_float = coalesce(d.cash_float,0)
                     - (d.total_earnings - coalesce(d.total_paid_out,0)),
        total_paid_out = d.total_earnings,
        updated_at = now()
  WHERE d.user_id IS NOT NULL
    AND (d.total_earnings - coalesce(d.total_paid_out,0)) > 0.005
    AND (d.total_earnings - coalesce(d.total_paid_out,0)
         - coalesce(d.cash_float,0)) <= 0.005;

  -- 3) Restaurants: pay balance (no float).
  INSERT INTO payout_requests (requester_id, requester_type, restaurant_id, amount,
    bank_name, bank_branch, bank_account_number, bank_account_holder,
    bank_account_type, status, batch_id, processed_at, admin_notes)
  SELECT r.owner_id, 'restaurant', r.id,
         round((r.total_earnings - coalesce(r.total_paid_out,0))::numeric, 2),
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

NOTIFY pgrst, 'reload schema';
