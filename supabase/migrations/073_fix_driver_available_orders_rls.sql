-- Migration 073: Fix drivers_select_available_orders RLS policy
-- Previously only allowed drivers to see 'ready' or old 'pending' orders.
-- Now allows all unassigned orders: pending, confirmed, preparing, ready.

DROP POLICY IF EXISTS drivers_select_available_orders ON orders;

CREATE POLICY drivers_select_available_orders ON orders
  FOR SELECT
  USING (
    driver_id IS NULL
    AND status IN ('pending', 'confirmed', 'preparing', 'ready')
    AND EXISTS (SELECT 1 FROM drivers d WHERE d.user_id = auth.uid())
  );
