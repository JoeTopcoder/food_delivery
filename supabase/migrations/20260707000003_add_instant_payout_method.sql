-- Add payout_method and instant_fee_cents to stripe_payout_requests
ALTER TABLE stripe_payout_requests
  ADD COLUMN IF NOT EXISTS payout_method text NOT NULL DEFAULT 'standard'
    CHECK (payout_method IN ('standard', 'instant')),
  ADD COLUMN IF NOT EXISTS instant_fee_cents integer NOT NULL DEFAULT 0;

COMMENT ON COLUMN stripe_payout_requests.payout_method IS 'standard = bank transfer (2-3 days); instant = debit card (~30 min, 1.5% fee)';
COMMENT ON COLUMN stripe_payout_requests.instant_fee_cents IS 'Stripe instant payout fee in cents (1.5%, min 50¢). Zero for standard payouts.';
