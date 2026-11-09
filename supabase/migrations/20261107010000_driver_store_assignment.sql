-- Dedicate a driver to a store. A driver with assigned_restaurant_id set only
-- receives that store's orders; a driver with it NULL keeps the default radius
-- pool. A dedicated store's orders are reserved for its driver(s) for a grace
-- period, after which any unclaimed one falls back to the general radius pool
-- so it can't get stranded if the dedicated driver is offline/full.
BEGIN;

ALTER TABLE drivers
  ADD COLUMN IF NOT EXISTS assigned_restaurant_id uuid
  REFERENCES restaurants(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_drivers_assigned_restaurant
  ON drivers (assigned_restaurant_id)
  WHERE assigned_restaurant_id IS NOT NULL;

-- Minutes a dedicated store's order stays reserved before general drivers see it.
INSERT INTO app_config (key, value)
SELECT 'dedicated_driver_grace_minutes', '5'
WHERE NOT EXISTS (SELECT 1 FROM app_config WHERE key = 'dedicated_driver_grace_minutes');

COMMIT;

NOTIFY pgrst, 'reload schema';
