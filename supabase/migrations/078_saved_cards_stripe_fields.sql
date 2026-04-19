-- Add Stripe-specific columns to saved_cards for proper card reuse
ALTER TABLE saved_cards
  ADD COLUMN IF NOT EXISTS stripe_payment_method_id TEXT,
  ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT,
  ADD COLUMN IF NOT EXISTS exp_month INT,
  ADD COLUMN IF NOT EXISTS exp_year INT;

-- Add stripe_customer_id to users table if not already present
ALTER TABLE users
  ADD COLUMN IF NOT EXISTS stripe_customer_id TEXT;

-- Index for fast lookup by Stripe payment method ID
CREATE INDEX IF NOT EXISTS idx_saved_cards_stripe_pm_id
  ON saved_cards (stripe_payment_method_id)
  WHERE stripe_payment_method_id IS NOT NULL;

-- Index for fast customer lookup
CREATE INDEX IF NOT EXISTS idx_users_stripe_customer_id
  ON users (stripe_customer_id)
  WHERE stripe_customer_id IS NOT NULL;
