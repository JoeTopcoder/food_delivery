-- Promotional banners linked to restaurants (ads)
CREATE TABLE IF NOT EXISTS banners (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  title TEXT NOT NULL,
  subtitle TEXT,
  image_url TEXT,
  restaurant_id UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  is_active BOOLEAN NOT NULL DEFAULT true,
  sort_order INT NOT NULL DEFAULT 0,
  starts_at TIMESTAMPTZ,
  ends_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for active banners query
CREATE INDEX IF NOT EXISTS idx_banners_active ON banners (is_active, sort_order) WHERE is_active = true;

-- RLS
ALTER TABLE banners ENABLE ROW LEVEL SECURITY;

-- Everyone can read active banners
CREATE POLICY banners_select ON banners FOR SELECT USING (true);

-- Only admins can insert/update/delete
CREATE POLICY banners_admin_insert ON banners FOR INSERT
  WITH CHECK (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY banners_admin_update ON banners FOR UPDATE
  USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY banners_admin_delete ON banners FOR DELETE
  USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
