-- Earnings balance is now sourced from earnings_ledger.
-- Zero out the legacy total_earnings / total_paid_out columns so they no
-- longer produce stale values on the wallet screen.
UPDATE public.drivers SET total_earnings = 0, total_paid_out = 0;
UPDATE public.restaurants SET total_paid_out = 0;
