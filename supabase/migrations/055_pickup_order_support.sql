-- ============================================================================
-- Migration 055: Pickup Order Support
-- Adds is_pickup flag and pickup_fee column to orders table
-- ============================================================================

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS is_pickup BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS pickup_fee DOUBLE PRECISION;

-- Index for filtering pickup vs delivery orders
CREATE INDEX IF NOT EXISTS idx_orders_is_pickup ON orders(is_pickup);

COMMENT ON COLUMN orders.is_pickup IS 'True when customer chooses to pick up from the restaurant';
COMMENT ON COLUMN orders.pickup_fee IS 'Service fee charged for pickup orders (lower than delivery_fee)';
