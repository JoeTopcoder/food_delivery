-- ============================================================================
-- SECURITY HARDENING: lock down three SECURITY DEFINER functions that were
-- executable by anon/authenticated and either leaked data or trusted a
-- caller-supplied id. Found by a live read-only audit (Oct 1 2026).
--
--  1. preview_payout_batch()        -> leaked ALL driver/restaurant bank
--                                      account numbers to anyone with the
--                                      public anon key (HTTP 200). Now admin-only.
--  2. issue_apology_coupon(...)     -> SECURITY DEFINER + caller-supplied
--                                      p_user_id with no auth tie: any client
--                                      could mint discount coupons for any
--                                      account. Now backend/trigger-only.
--  3. dineout_confirm_reservation() -> a customer could confirm their OWN
--                                      reservation and flip deposit_status to
--                                      'paid' without paying. Now the paid/
--                                      confirmed transition is service_role /
--                                      admin / restaurant-owner only.
--
-- All three are owned by postgres and run SECURITY DEFINER, so existing
-- triggers (apology) and future service_role edge functions (dineout deposit,
-- payout batch run as admin) keep working. No Flutter/edge caller invokes (1)
-- or (3) as an end user today; (1) is called by the admin payout screen as an
-- authenticated admin and is preserved via the is_admin() guard.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 1. preview_payout_batch(): admin-only. Rewritten in plpgsql to guard, then
--    return the same rows. REVOKE anon entirely; keep authenticated so admins
--    can call it, but the body refuses anyone who is not an aal2 admin.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.preview_payout_batch()
 RETURNS TABLE(entity_type text, entity_name text, bank_name text, bank_branch text,
               bank_account_number text, bank_account_holder text, bank_account_type text,
               amount numeric, has_bank boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
BEGIN
  IF NOT (public.is_admin() OR COALESCE(auth.role(),'') = 'service_role') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
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
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.preview_payout_batch() FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.preview_payout_batch() TO authenticated, service_role;

-- ---------------------------------------------------------------------------
-- 2. issue_apology_coupon(...): backend/trigger-only. The app never calls it
--    directly; it is invoked by SECURITY DEFINER triggers (owned by postgres,
--    which retain EXECUTE) and should only ever be driven server-side.
--    Removing the anon/authenticated grant closes the coupon-minting hole
--    without touching the trigger path.
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.issue_apology_coupon(uuid, text, uuid, numeric, text)
  FROM anon, authenticated, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.issue_apology_coupon(uuid, text, uuid, numeric, text)
  TO service_role;

-- ---------------------------------------------------------------------------
-- 3. dineout_confirm_reservation(): only service_role / admin / the owning
--    restaurant may confirm a reservation and mark its deposit paid. A
--    customer can no longer flip their own deposit to 'paid' without paying.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.dineout_confirm_reservation(
  p_reservation_id uuid, p_payment_intent_id text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE r public.dineout_reservations;
BEGIN
  SELECT * INTO r FROM dineout_reservations WHERE id=p_reservation_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;

  -- Confirming a reservation settles its deposit, so only the platform
  -- (service_role / admin) or the owning restaurant may do it -- never the
  -- customer themselves, who would otherwise mark their own deposit paid.
  IF NOT (public.current_user_owns_restaurant(r.restaurant_id)
          OR public.is_admin()
          OR COALESCE(auth.role(),'') = 'service_role') THEN
    RAISE EXCEPTION 'FORBIDDEN' USING ERRCODE = '42501';
  END IF;

  IF r.status='confirmed' THEN RETURN to_jsonb(r); END IF;   -- idempotent
  IF r.status NOT IN ('hold','pending_payment') THEN RAISE EXCEPTION 'BAD_STATE'; END IF;

  UPDATE dineout_reservations SET status='confirmed',
     deposit_status = CASE WHEN deposit_amount>0 THEN 'paid' ELSE deposit_status END,
     payment_intent_id = COALESCE(p_payment_intent_id, payment_intent_id),
     hold_expires_at = NULL, updated_at = now()
   WHERE id=p_reservation_id RETURNING * INTO r;

  INSERT INTO dineout_status_history(reservation_id, from_status, to_status, changed_by, note)
    VALUES (p_reservation_id, 'pending_payment', 'confirmed', auth.uid(), 'confirmed');
  RETURN to_jsonb(r);
END;
$function$;

REVOKE EXECUTE ON FUNCTION public.dineout_confirm_reservation(uuid, text) FROM anon, PUBLIC;
GRANT  EXECUTE ON FUNCTION public.dineout_confirm_reservation(uuid, text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
