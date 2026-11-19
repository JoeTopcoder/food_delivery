-- Let an admin pay a driver their earnings in CASH, even when the driver has no
-- bank details on file (the batch run only pays bank-equipped payees). A cash
-- payout records a settled (status='completed') driver payout_request — so it
-- counts in the Financials "Driver Payouts Completed" and reduces the
-- outstanding liability, exactly like a bank batch payout — and advances
-- drivers.total_paid_out so the next preview shows less owed.
BEGIN;

-- 1) Expose entity_id in the payout preview so the UI can target a specific
--    driver/restaurant. Still admin-gated; bank fields unchanged.
DROP FUNCTION IF EXISTS public.preview_payout_batch();
CREATE FUNCTION public.preview_payout_batch()
 RETURNS TABLE(entity_type text, entity_id uuid, entity_name text, bank_name text,
   bank_branch text, bank_account_number text, bank_account_holder text,
   bank_account_type text, amount numeric, has_bank boolean,
   earnings_balance numeric)
 LANGUAGE plpgsql STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT (public.is_admin() OR COALESCE(auth.role(),'') = 'service_role') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT 'driver', d.id, d.full_name, d.bank_name, d.bank_branch,
         d.bank_account_number, d.bank_account_holder, d.bank_account_type,
         round((d.total_earnings - coalesce(d.total_paid_out,0)
                - coalesce(d.cash_float,0))::numeric, 2),
         coalesce(trim(d.bank_account_number),'') <> '',
         round((d.total_earnings - coalesce(d.total_paid_out,0))::numeric, 2)
  FROM drivers d
  WHERE d.user_id IS NOT NULL
    AND ((d.total_earnings - coalesce(d.total_paid_out,0)) > 0.005
         OR (d.total_earnings - coalesce(d.total_paid_out,0)
             - coalesce(d.cash_float,0)) > 0.005)
  UNION ALL
  SELECT 'restaurant', r.id, r.name, r.bank_name, r.bank_branch,
         r.bank_account_number, r.bank_account_holder, r.bank_account_type,
         round((r.total_earnings - coalesce(r.total_paid_out,0))::numeric, 2),
         coalesce(trim(r.bank_account_number),'') <> '',
         round((r.total_earnings - coalesce(r.total_paid_out,0))::numeric, 2)
  FROM restaurants r
  WHERE r.owner_id IS NOT NULL
    AND (r.total_earnings - coalesce(r.total_paid_out,0)) > 0.005
  ORDER BY 1, 9 DESC;
END;
$function$;

-- 2) Record a cash payout to a driver.
CREATE OR REPLACE FUNCTION public.admin_pay_driver_cash(
  p_driver_id uuid, p_amount numeric)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_admin uuid;
  v_earnings numeric; v_paid numeric; v_balance numeric; v_user uuid;
  v_name text; v_amt numeric;
BEGIN
  v_admin := public.require_admin(auth.uid());
  v_amt := round(COALESCE(p_amount,0)::numeric, 2);
  IF v_amt <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

  SELECT user_id, full_name, COALESCE(total_earnings,0), COALESCE(total_paid_out,0)
    INTO v_user, v_name, v_earnings, v_paid
  FROM drivers WHERE id = p_driver_id FOR UPDATE;
  IF v_user IS NULL THEN RAISE EXCEPTION 'Driver not found'; END IF;

  v_balance := round((v_earnings - v_paid)::numeric, 2);  -- unpaid earnings
  IF v_amt > v_balance THEN
    RAISE EXCEPTION 'Cash payout % exceeds unpaid earnings %', v_amt, v_balance;
  END IF;

  -- Settled payout record (counts as a completed driver payout).
  INSERT INTO payout_requests (requester_id, requester_type, driver_id, amount,
    bank_name, bank_branch, bank_account_number, bank_account_holder,
    bank_account_type, status, processed_at, admin_notes)
  VALUES (v_user, 'driver', p_driver_id, v_amt,
    'CASH', 'CASH', 'CASH', COALESCE(v_name,'Driver'), 'cash',
    'completed', now(), 'Cash payout by admin');

  UPDATE drivers SET total_paid_out = v_paid + v_amt, updated_at = now()
  WHERE id = p_driver_id;

  RETURN jsonb_build_object('ok', true, 'driver_id', p_driver_id,
    'paid', v_amt, 'new_total_paid_out', v_paid + v_amt,
    'remaining_unpaid_earnings', round((v_balance - v_amt)::numeric, 2));
END; $fn$;

GRANT EXECUTE ON FUNCTION public.admin_pay_driver_cash(uuid, numeric) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
