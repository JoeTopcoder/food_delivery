-- Migration 105: Fix driver available orders RLS
-- The previous policy (020) only allowed 'ready' status and 'pending > 30min'.
-- This blocked 'confirmed' and 'preparing' orders from appearing in the driver feed,
-- causing the Find Orders tab to show empty even when orders exist.

DROP POLICY IF EXISTS drivers_select_available_orders ON orders;

CREATE POLICY drivers_select_available_orders ON orders
  FOR SELECT
  USING (
    driver_id IS NULL
    AND status IN ('pending', 'confirmed', 'preparing', 'ready')
    AND EXISTS (
      SELECT 1 FROM drivers d WHERE d.user_id = auth.uid()
    )
  );
