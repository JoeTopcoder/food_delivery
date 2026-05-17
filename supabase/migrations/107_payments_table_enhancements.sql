-- Expand the payments table to track all Stripe-required fields.
-- Uses IF NOT EXISTS / DO NOTHING guards so it is safe to re-run.

-- 1. Drop the restrictive status check so we can broaden it.
ALTER TABLE payments
  DROP CONSTRAINT IF EXISTS payments_status_check;

-- 2. Re-add with the full set of meaningful Stripe statuses.
ALTER TABLE payments
  ADD CONSTRAINT payments_status_check
  CHECK (status IN (
    'pending',
    'processing',
    'authorized',
    'completed',
    'failed',
    'cancelled',
    'refunded',
    'requires_payment_method'
  ));

-- 3. New columns (all with safe defaults so existing rows are untouched).
ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS currency             TEXT DEFAULT 'USD',
  ADD COLUMN IF NOT EXISTS gateway              TEXT DEFAULT 'stripe',
  ADD COLUMN IF NOT EXISTS paid_at              TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS payment_attempt_count INT  DEFAULT 0,
  ADD COLUMN IF NOT EXISTS refund_amount        DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS refund_reason        TEXT,
  ADD COLUMN IF NOT EXISTS idempotency_key      TEXT;

-- 4. Index for idempotency deduplication (webhook replays).
CREATE UNIQUE INDEX IF NOT EXISTS payments_idempotency_key_idx
  ON payments (idempotency_key)
  WHERE idempotency_key IS NOT NULL;

-- 5. Index for Stripe transaction_id lookups (webhook needs this).
CREATE INDEX IF NOT EXISTS payments_transaction_id_idx
  ON payments (transaction_id)
  WHERE transaction_id IS NOT NULL;
