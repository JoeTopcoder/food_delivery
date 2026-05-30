-- Each restaurant sub-order gets its own unique restaurant_order_number
-- visible only to that restaurant (e.g. RST-20260527-0001).
-- The master receipt_number on order_groups stays as the customer-facing number.

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS restaurant_order_number TEXT;

CREATE INDEX IF NOT EXISTS idx_orders_restaurant_order_number
  ON orders(restaurant_order_number);

-- RLS: restaurants can only read their own restaurant_orders (sub-orders)
-- The existing "restaurant sees orders for its restaurant_id" policy handles this,
-- but make it explicit for restaurant_order_number queries.
-- (existing policies on orders table already filter by restaurant_id = current restaurant)
