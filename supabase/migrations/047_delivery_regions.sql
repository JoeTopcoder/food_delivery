-- ── Delivery Regions (admin-managed zones) ──────────────────────────────────
-- Each region is a circle defined by a center point + radius.
-- Customers whose delivery address falls outside every active region
-- are blocked from placing orders.

CREATE TABLE IF NOT EXISTS delivery_regions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  radius_km DOUBLE PRECISION NOT NULL DEFAULT 10.0,
  is_active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE delivery_regions ENABLE ROW LEVEL SECURITY;

-- Everyone can read regions (customers need them for the zone check).
CREATE POLICY delivery_regions_select ON delivery_regions
  FOR SELECT USING (true);

-- Only admins can insert / update / delete.
CREATE POLICY delivery_regions_admin ON delivery_regions
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
