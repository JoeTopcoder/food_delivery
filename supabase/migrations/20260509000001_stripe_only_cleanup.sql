-- Stripe-Only Payment Gateway Migration
-- Cleans up database for Stripe-only operation
-- All card payments now route through Stripe

BEGIN;

-- Drop/mark unused columns for non-Stripe payment methods
-- (These are left in place for backward compatibility but won't be used)

-- Update payments table: ensure all card payments are marked as stripe gateway
UPDATE payments
SET gateway = 'stripe'
WHERE method = 'card'
  AND gateway IS NULL
  AND status != 'failed';

-- Mark any pending NCB, WiPay, or Lunipay transactions as cancelled
UPDATE payments
SET status = 'cancelled'
WHERE gateway IN ('ncb', 'wipay', 'lunipay')
  AND status IN ('pending', 'processing');

-- Ensure saved_cards only references valid stripe customer IDs
DELETE FROM saved_cards
WHERE card_brand NOT IN ('visa', 'mastercard', 'amex', 'discover')
  AND verification_id NOT LIKE 'pi_%'
  AND verification_id NOT LIKE 'pi_test_%';

-- Clear any test/incomplete payment intents
DELETE FROM payments
WHERE gateway = 'stripe'
  AND status = 'pending'
  AND created_at < NOW() - INTERVAL '7 days';

-- Ensure payment method preferences are set (if column exists)
ALTER TABLE users ADD COLUMN IF NOT EXISTS preferred_payment_method TEXT DEFAULT 'card';
UPDATE users
SET preferred_payment_method = 'card'
WHERE preferred_payment_method IN ('ncb', 'wipay', 'lunipay')
  OR preferred_payment_method IS NULL;

COMMIT;
