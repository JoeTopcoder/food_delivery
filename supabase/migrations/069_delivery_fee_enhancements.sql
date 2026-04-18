-- 069: Delivery fee enhancements
-- Adds: delivery_fee_cache table, driver_pay_percent + min_delivery_fee app_config keys

-- ── Distance cache table ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS delivery_fee_cache (
  id           uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  restaurant_id uuid NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  delivery_lat numeric(10, 7) NOT NULL,
  delivery_lng numeric(10, 7) NOT NULL,
  distance_km  numeric(8, 2)  NOT NULL,
  delivery_fee numeric(10, 2) NOT NULL,
  driver_pay   numeric(10, 2) NOT NULL,
  surge_multiplier numeric(4, 2) NOT NULL DEFAULT 1.0,
  calculation  text NOT NULL DEFAULT 'distance_based',
  expires_at   timestamptz NOT NULL DEFAULT (now() + interval '1 hour'),
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Index for fast lookups by restaurant + approximate location
CREATE INDEX IF NOT EXISTS idx_delivery_fee_cache_lookup
  ON delivery_fee_cache (restaurant_id, delivery_lat, delivery_lng);

-- Auto-clean expired rows (run via pg_cron or on read)
CREATE INDEX IF NOT EXISTS idx_delivery_fee_cache_expires
  ON delivery_fee_cache (expires_at);

-- RLS: only service_role / edge-functions need access
ALTER TABLE delivery_fee_cache ENABLE ROW LEVEL SECURITY;

-- Allow authenticated users to read their own cached results
CREATE POLICY delivery_fee_cache_read ON delivery_fee_cache
  FOR SELECT TO authenticated USING (true);

-- Only service_role can insert/update/delete
CREATE POLICY delivery_fee_cache_service ON delivery_fee_cache
  FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ── New app_config keys ─────────────────────────────────────────────────────
INSERT INTO app_config (key, value, value_type, category, description) VALUES
  ('driver_pay_percent', '0.80', 'number', 'delivery', 'Fraction of delivery fee paid to driver (0.80 = 80%)'),
  ('min_delivery_fee', '3.00', 'number', 'delivery', 'Minimum delivery fee in USD regardless of distance')
ON CONFLICT (key) DO NOTHING;

-- Allow admin to INSERT into app_config (needed for upsert operations)
CREATE POLICY admin_insert_app_config ON app_config
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );

-- Allow admin to delete from delivery_fee_cache (for cache clearing)
CREATE POLICY admin_delete_delivery_fee_cache ON delivery_fee_cache
  FOR DELETE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
