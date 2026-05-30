-- =============================================================================
-- master_orders   : one per customer checkout (the customer-facing order)
-- restaurant_orders : one per restaurant within a master_order
-- restaurant_order_items : line items per restaurant_order
-- restaurant_order_item_sides : sides per line item
-- =============================================================================

-- ─── 1. master_orders ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS master_orders (
  id                    UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id           UUID        NOT NULL REFERENCES auth.users(id),
  master_order_number   TEXT        UNIQUE,
  status                TEXT        NOT NULL DEFAULT 'pending',
  -- pending | accepted | preparing | ready_for_pickup | out_for_delivery
  -- | delivered | cancelled | partially_cancelled
  delivery_address      TEXT        NOT NULL DEFAULT '',
  delivery_latitude     FLOAT8,
  delivery_longitude    FLOAT8,
  payment_method        TEXT        NOT NULL DEFAULT 'stripe',
  payment_status        TEXT        NOT NULL DEFAULT 'pending',
  subtotal              FLOAT8      NOT NULL DEFAULT 0,
  delivery_fee          FLOAT8      NOT NULL DEFAULT 0,
  extra_stop_fee        FLOAT8      NOT NULL DEFAULT 0,
  platform_fee          FLOAT8      NOT NULL DEFAULT 0,
  tax_amount            FLOAT8      NOT NULL DEFAULT 0,
  discount              FLOAT8      NOT NULL DEFAULT 0,
  total_amount          FLOAT8      NOT NULL DEFAULT 0,
  driver_id             UUID        REFERENCES auth.users(id),
  notes                 TEXT,
  is_pickup             BOOLEAN     NOT NULL DEFAULT FALSE,
  contactless_delivery  BOOLEAN     NOT NULL DEFAULT FALSE,
  driver_tip            FLOAT8,
  post_delivery_tip     FLOAT8,
  delivery_otp          TEXT,
  delivery_otp_verified BOOLEAN,
  delivery_photo_url    TEXT,
  estimated_delivery_at TIMESTAMPTZ,
  delivered_at          TIMESTAMPTZ,
  cancelled_at          TIMESTAMPTZ,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_master_orders_customer ON master_orders(customer_id);
CREATE INDEX IF NOT EXISTS idx_master_orders_driver   ON master_orders(driver_id);
CREATE INDEX IF NOT EXISTS idx_master_orders_status   ON master_orders(status);
CREATE INDEX IF NOT EXISTS idx_master_orders_created  ON master_orders(created_at DESC);

-- ─── 2. restaurant_orders ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS restaurant_orders (
  id                      UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  master_order_id         UUID        NOT NULL REFERENCES master_orders(id) ON DELETE CASCADE,
  restaurant_id           UUID        NOT NULL REFERENCES restaurants(id),
  restaurant_order_number TEXT        UNIQUE,
  status                  TEXT        NOT NULL DEFAULT 'pending',
  -- pending | accepted | preparing | ready | cancelled
  subtotal                FLOAT8      NOT NULL DEFAULT 0,
  delivery_fee            FLOAT8      NOT NULL DEFAULT 0,
  commission_rate         FLOAT8,
  commission_amount       FLOAT8,
  distance_km             FLOAT8,
  estimated_prep_minutes  INT,
  notes                   TEXT,
  sequence_in_group       INT         NOT NULL DEFAULT 1,
  delivery_otp            TEXT,
  pickup_status           TEXT        NOT NULL DEFAULT 'pending',
  -- pending | arrived | picked_up
  confirmed_at            TIMESTAMPTZ,
  preparing_at            TIMESTAMPTZ,
  ready_at                TIMESTAMPTZ,
  cancelled_at            TIMESTAMPTZ,
  picked_up_at            TIMESTAMPTZ,
  created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_restaurant_orders_master     ON restaurant_orders(master_order_id);
CREATE INDEX IF NOT EXISTS idx_restaurant_orders_restaurant ON restaurant_orders(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_restaurant_orders_status     ON restaurant_orders(status);
CREATE INDEX IF NOT EXISTS idx_restaurant_orders_created    ON restaurant_orders(created_at DESC);

-- ─── 3. restaurant_order_items ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS restaurant_order_items (
  id                   UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_order_id  UUID        NOT NULL REFERENCES restaurant_orders(id) ON DELETE CASCADE,
  menu_item_id         UUID        REFERENCES menus(id),
  item_name            TEXT        NOT NULL,
  price                FLOAT8      NOT NULL,
  quantity             INT         NOT NULL DEFAULT 1,
  notes                TEXT,
  created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_roi_restaurant_order ON restaurant_order_items(restaurant_order_id);

-- ─── 4. restaurant_order_item_sides ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS restaurant_order_item_sides (
  id                        UUID    PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_order_item_id  UUID    NOT NULL
                              REFERENCES restaurant_order_items(id) ON DELETE CASCADE,
  side_name                 TEXT    NOT NULL,
  side_price                FLOAT8  NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS idx_rois_item ON restaurant_order_item_sides(restaurant_order_item_id);

-- =============================================================================
-- ROW LEVEL SECURITY
-- =============================================================================

ALTER TABLE master_orders              ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurant_orders          ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurant_order_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE restaurant_order_item_sides ENABLE ROW LEVEL SECURITY;

-- ── master_orders ─────────────────────────────────────────────────────────────
CREATE POLICY "mo_customer_select" ON master_orders FOR SELECT
  USING (customer_id = auth.uid());

CREATE POLICY "mo_driver_select" ON master_orders FOR SELECT
  USING (driver_id = auth.uid());

CREATE POLICY "mo_admin_all" ON master_orders FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "mo_service_role" ON master_orders FOR ALL
  USING (auth.role() = 'service_role');

-- ── restaurant_orders ─────────────────────────────────────────────────────────
-- Restaurant owners manage their own restaurant_orders
CREATE POLICY "ro_restaurant_all" ON restaurant_orders FOR ALL
  USING (
    restaurant_id IN (SELECT id FROM restaurants WHERE owner_id = auth.uid())
  );

-- Customers read restaurant_orders belonging to their master_orders
CREATE POLICY "ro_customer_select" ON restaurant_orders FOR SELECT
  USING (
    master_order_id IN (
      SELECT id FROM master_orders WHERE customer_id = auth.uid()
    )
  );

-- Drivers read restaurant_orders for their assigned master_orders
CREATE POLICY "ro_driver_select" ON restaurant_orders FOR SELECT
  USING (
    master_order_id IN (
      SELECT id FROM master_orders WHERE driver_id = auth.uid()
    )
  );

CREATE POLICY "ro_admin_all" ON restaurant_orders FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "ro_service_role" ON restaurant_orders FOR ALL
  USING (auth.role() = 'service_role');

-- ── restaurant_order_items ────────────────────────────────────────────────────
CREATE POLICY "roi_restaurant_select" ON restaurant_order_items FOR SELECT
  USING (
    restaurant_order_id IN (
      SELECT ro.id FROM restaurant_orders ro
      JOIN restaurants r ON ro.restaurant_id = r.id
      WHERE r.owner_id = auth.uid()
    )
  );

CREATE POLICY "roi_customer_select" ON restaurant_order_items FOR SELECT
  USING (
    restaurant_order_id IN (
      SELECT ro.id FROM restaurant_orders ro
      JOIN master_orders mo ON ro.master_order_id = mo.id
      WHERE mo.customer_id = auth.uid()
    )
  );

CREATE POLICY "roi_driver_select" ON restaurant_order_items FOR SELECT
  USING (
    restaurant_order_id IN (
      SELECT ro.id FROM restaurant_orders ro
      JOIN master_orders mo ON ro.master_order_id = mo.id
      WHERE mo.driver_id = auth.uid()
    )
  );

CREATE POLICY "roi_admin_all" ON restaurant_order_items FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "roi_service_role" ON restaurant_order_items FOR ALL
  USING (auth.role() = 'service_role');

-- ── restaurant_order_item_sides ───────────────────────────────────────────────
CREATE POLICY "rois_access" ON restaurant_order_item_sides FOR SELECT
  USING (
    restaurant_order_item_id IN (
      SELECT roi.id FROM restaurant_order_items roi
      JOIN restaurant_orders ro  ON roi.restaurant_order_id = ro.id
      JOIN master_orders     mo  ON ro.master_order_id      = mo.id
      WHERE mo.customer_id = auth.uid()
         OR mo.driver_id   = auth.uid()
         OR ro.restaurant_id IN (
               SELECT id FROM restaurants WHERE owner_id = auth.uid()
            )
    )
  );

CREATE POLICY "rois_admin_all" ON restaurant_order_item_sides FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

CREATE POLICY "rois_service_role" ON restaurant_order_item_sides FOR ALL
  USING (auth.role() = 'service_role');

-- =============================================================================
-- AUTO STATUS ROLLUP
-- When any restaurant_order.status changes, recalculate master_order.status
-- (does NOT overwrite statuses set by the driver: out_for_delivery, delivered)
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_recalculate_master_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_statuses  TEXT[];
  v_new       TEXT;
BEGIN
  SELECT ARRAY_AGG(status) INTO v_statuses
  FROM   restaurant_orders
  WHERE  master_order_id = NEW.master_order_id;

  IF v_statuses IS NULL THEN RETURN NEW; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM unnest(v_statuses) s(v) WHERE v <> 'cancelled'
  ) THEN
    v_new := 'cancelled';
  ELSIF 'cancelled' = ANY(v_statuses) THEN
    v_new := 'partially_cancelled';
  ELSIF NOT EXISTS (
    SELECT 1 FROM unnest(v_statuses) s(v)
    WHERE  v NOT IN ('ready', 'picked_up')
  ) THEN
    v_new := 'ready_for_pickup';
  ELSIF 'preparing' = ANY(v_statuses) THEN
    v_new := 'preparing';
  ELSIF 'accepted' = ANY(v_statuses) THEN
    v_new := 'accepted';
  ELSE
    v_new := 'pending';
  END IF;

  UPDATE master_orders
  SET    status     = v_new,
         updated_at = NOW()
  WHERE  id = NEW.master_order_id
    AND  status NOT IN ('out_for_delivery', 'delivered', 'cancelled');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ro_status_rollup ON restaurant_orders;
CREATE TRIGGER trg_ro_status_rollup
  AFTER UPDATE OF status ON restaurant_orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION fn_recalculate_master_status();

-- =============================================================================
-- ADMIN CONFIG — multi-restaurant feature flags
-- =============================================================================
INSERT INTO app_config (key, value, description) VALUES
  ('enable_multi_restaurant_orders', 'true', 'Feature flag: allow ordering from multiple restaurants'),
  ('max_restaurants_per_order',       '3',   'Hard cap on restaurants per multi-restaurant checkout'),
  ('multi_restaurant_radius_km',      '15',  'Max km between any two restaurants in a multi-restaurant order')
ON CONFLICT (key) DO NOTHING;
