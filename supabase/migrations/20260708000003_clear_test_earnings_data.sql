-- One-time cleanup: remove all test earnings / payout data so the
-- lock-split fix can be verified fresh. Safe to run in dev/test only.

TRUNCATE TABLE public.payout_request_ledger_entries CASCADE;
TRUNCATE TABLE public.stripe_payout_requests          CASCADE;
TRUNCATE TABLE public.earnings_ledger                 CASCADE;
