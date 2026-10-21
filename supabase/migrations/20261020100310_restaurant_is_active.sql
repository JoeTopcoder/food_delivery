-- Admin deactivate switch: is_active=false hides a restaurant from ALL customer
-- surfaces (distinct from is_open, which only shows a "Closed" badge, and from
-- is_verified, which is the partner-approval state).
ALTER TABLE restaurants ADD COLUMN IF NOT EXISTS is_active BOOLEAN NOT NULL DEFAULT TRUE;
CREATE INDEX IF NOT EXISTS idx_restaurants_is_active ON restaurants (is_active);
COMMENT ON COLUMN restaurants.is_active IS
  'Admin master switch. false = hidden from every customer surface. Independent of is_open (open/closed badge) and is_verified (partner approval).';
NOTIFY pgrst, 'reload schema';
