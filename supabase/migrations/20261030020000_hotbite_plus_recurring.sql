-- HotBite+ recurring (monthly auto-renewing) membership via a real Stripe
-- Subscription. Adds the fields needed to link the membership to its Stripe
-- subscription + price and track the billing period.

ALTER TABLE membership_plans
  ADD COLUMN IF NOT EXISTS stripe_product_id text,
  ADD COLUMN IF NOT EXISTS stripe_price_id   text;

ALTER TABLE customer_memberships
  ADD COLUMN IF NOT EXISTS stripe_subscription_id text,
  ADD COLUMN IF NOT EXISTS stripe_customer_id     text,
  ADD COLUMN IF NOT EXISTS current_period_end     timestamptz;

-- One active (or pending) membership per user.
CREATE UNIQUE INDEX IF NOT EXISTS customer_memberships_one_live_per_user
  ON customer_memberships(user_id)
  WHERE status IN ('active','pending');

NOTIFY pgrst, 'reload schema';
