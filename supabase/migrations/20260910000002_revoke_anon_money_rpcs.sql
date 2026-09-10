-- CRITICAL SECURITY FIX: anyone with the app could mint wallet money.
--
-- Proven live, as an ANONYMOUS caller using the anon key that ships in every
-- copy of the app (no account, no login):
--   wallet_credit('<any user>', 999999)          -> succeeded
--   wallet_deposit('<any user>', 999999)          -> succeeded
--   wallet_award_cashback('<any user>', ...)      -> succeeded
--   mark_payout_paid('<any payout>')              -> succeeded
-- A victim wallet went from ~0 to 1,999,998 in one transaction (rolled back
-- during testing).
--
-- Root cause: these SECURITY DEFINER functions take a caller-supplied
-- p_user_id and amount, perform no identity check, and were granted to PUBLIC,
-- which anon inherits.
--
-- This migration removes anon/PUBLIC EXECUTE from every wallet, earning and
-- payout primitive. The app calls these as an authenticated user, never as
-- anon, so nothing legitimate breaks. Payout-control functions, which no
-- client has any business calling, are locked to service_role.
--
-- NOTE — not fully closed by this migration: the client still calls
-- wallet_credit / wallet_deposit / credit_earning directly, so a logged-in
-- user can still credit a wallet. Removing anon access stops the no-account
-- attack (the worst, untraceable one); pinning those credits to a
-- server-verified payment is a separate change flagged to the owner.

DO $revoke$
DECLARE
  r RECORD;
  -- Backend-only: no client path should ever reach these.
  backend_only TEXT[] := ARRAY[
    'wallet_award_cashback','mark_payout_paid','mark_payout_failed',
    'apply_wallet_debt','lock_ledger_entries_for_payout',
    'unlock_ledger_entries_for_payout','update_earning_tier',
    'expire_old_credits','get_driver_wallet_summary','get_user_earnings_summary'
  ];
  -- Called by the app as an authenticated user, so they keep that grant. The
  -- anon grant is still removed.
  client_called TEXT[] := ARRAY[
    'wallet_credit','wallet_deposit','credit_earning','wallet_pay',
    'wallet_deduct','wallet_transfer','process_order_referral_earnings',
    'reserve_laundry_payment','link_student_by_wallet_id'
  ];
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig, p.proname
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname = ANY(backend_only || client_called)
  LOOP
    -- anon inherits EXECUTE from PUBLIC, so PUBLIC is the grant that matters.
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);

    IF r.proname = ANY(backend_only) THEN
      EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM authenticated', r.sig);
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
    ELSE
      EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
    END IF;
  END LOOP;
END
$revoke$;

NOTIFY pgrst, 'reload schema';
