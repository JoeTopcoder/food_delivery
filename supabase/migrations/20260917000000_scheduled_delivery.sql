-- Scheduled delivery: an order can be requested for a future time. The order is
-- created normally but held from drivers until close to its slot.
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS scheduled_for timestamptz;

ALTER TABLE concierge_cart_drafts
  ADD COLUMN IF NOT EXISTS scheduled_for timestamptz;

-- Fast lookup of due/pending scheduled orders.
CREATE INDEX IF NOT EXISTS idx_orders_scheduled_for
  ON orders (scheduled_for)
  WHERE scheduled_for IS NOT NULL;

NOTIFY pgrst, 'reload schema';
