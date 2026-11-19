-- Cash payout for a restaurant OR supermarket, mirroring admin_pay_driver_cash.
-- Restaurants and grocery stores share the restaurants table (store_type), and
-- both carry total_earnings / total_paid_out, so one RPC covers both. Records a
-- completed payout_requests row (requester_type='restaurant') and advances
-- total_paid_out so the payout batch no longer shows the amount as owed.
CREATE OR REPLACE FUNCTION public.admin_pay_restaurant_cash(
  p_restaurant_id uuid, p_amount numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin uuid;
  v_owner uuid; v_name text; v_earnings numeric; v_paid numeric;
  v_balance numeric; v_amt numeric;
BEGIN
  v_admin := public.require_admin(auth.uid());
  v_amt := round(COALESCE(p_amount,0)::numeric, 2);
  IF v_amt <= 0 THEN RAISE EXCEPTION 'Amount must be positive'; END IF;

  SELECT owner_id, name, COALESCE(total_earnings,0), COALESCE(total_paid_out,0)
    INTO v_owner, v_name, v_earnings, v_paid
  FROM restaurants WHERE id = p_restaurant_id FOR UPDATE;
  IF v_owner IS NULL THEN RAISE EXCEPTION 'Restaurant not found or has no owner'; END IF;

  v_balance := round((v_earnings - v_paid)::numeric, 2);  -- unpaid earnings
  IF v_amt > v_balance THEN
    RAISE EXCEPTION 'Cash payout % exceeds unpaid earnings %', v_amt, v_balance;
  END IF;

  INSERT INTO payout_requests (requester_id, requester_type, restaurant_id, amount,
    bank_name, bank_branch, bank_account_number, bank_account_holder,
    bank_account_type, status, processed_at, admin_notes)
  VALUES (v_owner, 'restaurant', p_restaurant_id, v_amt,
    'CASH', 'CASH', 'CASH', COALESCE(v_name,'Store'), 'cash',
    'completed', now(), 'Cash payout by admin');

  UPDATE restaurants SET total_paid_out = v_paid + v_amt, updated_at = now()
  WHERE id = p_restaurant_id;

  RETURN jsonb_build_object('ok', true, 'restaurant_id', p_restaurant_id,
    'paid', v_amt, 'new_total_paid_out', v_paid + v_amt,
    'remaining_unpaid_earnings', round((v_balance - v_amt)::numeric, 2));
END; $function$;

REVOKE ALL ON FUNCTION public.admin_pay_restaurant_cash(uuid, numeric) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_pay_restaurant_cash(uuid, numeric) TO authenticated;

NOTIFY pgrst, 'reload schema';
