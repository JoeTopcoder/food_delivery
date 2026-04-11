-- Migration 020: Allow drivers to see available (unassigned) orders
-- Drivers need to see orders with status 'ready' or pending > 30 min 
-- where driver_id IS NULL so they can accept them.

-- Add policy: drivers can SELECT unassigned orders that are ready or stale pending
CREATE POLICY drivers_select_available_orders ON orders
  FOR SELECT
  USING (
    driver_id IS NULL
    AND (
      status = 'ready'
      OR (status = 'pending' AND ordered_at < NOW() - INTERVAL '30 minutes')
    )
    AND EXISTS (
      SELECT 1 FROM drivers d WHERE d.user_id = auth.uid()
    )
  );
