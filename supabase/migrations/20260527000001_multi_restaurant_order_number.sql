-- Add a single customer-facing receipt number to order_groups.
-- Multi-restaurant sub-orders all share this one number so the customer
-- sees one order rather than N orders (one per restaurant).

ALTER TABLE order_groups
  ADD COLUMN IF NOT EXISTS receipt_number TEXT;

-- Index for fast lookup by receipt number
CREATE INDEX IF NOT EXISTS idx_order_groups_receipt_number
  ON order_groups(receipt_number);
