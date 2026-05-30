-- ============================================================
-- Multi-Restaurant Ordering Support
-- Safe extension — existing single-restaurant flow unchanged.
-- ============================================================

-- ── 1. order_groups  (the "parent order" record) ─────────────
CREATE TABLE IF NOT EXISTS order_groups (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  total_restaurants     INTEGER NOT NULL DEFAULT 1,
  subtotal              DOUBLE PRECISION NOT NULL DEFAULT 0,
  delivery_fee          DOUBLE PRECISION NOT NULL DEFAULT 0,
  extra_stop_fee        DOUBLE PRECISION NOT NULL DEFAULT 0,
  tax_amount            DOUBLE PRECISION NOT NULL DEFAULT 0,
  discount              DOUBLE PRECISION NOT NULL DEFAULT 0,
  total_amount          DOUBLE PRECISION NOT NULL DEFAULT 0,
  payment_method        TEXT,
  payment_status        TEXT NOT NULL DEFAULT 'pending'
                          CHECK (payment_status IN ('pending','paid','failed','refunded')),
  delivery_address      TEXT,
  delivery_latitude     DOUBLE PRECISION,
  delivery_longitude    DOUBLE PRECISION,
  notes                 TEXT,
  status                TEXT NOT NULL DEFAULT 'pending'
                          CHECK (status IN ('pending','confirmed','preparing',
                                            'ready','picked_up','on_the_way',
                                            'delivered','cancelled')),
  stripe_payment_intent_id TEXT,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── 2. Extend orders with group linkage (safe: nullable) ──────
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS order_group_id      UUID REFERENCES order_groups(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS is_multi_restaurant  BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS sequence_in_group    INTEGER;   -- 1 = first pickup stop, 2 = second …

-- ── 3. delivery_tasks  (one task per group delivery) ─────────
CREATE TABLE IF NOT EXISTS delivery_tasks (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_group_id              UUID REFERENCES order_groups(id) ON DELETE CASCADE,
  order_id                    UUID REFERENCES orders(id) ON DELETE CASCADE, -- single-restaurant fallback
  driver_id                   UUID REFERENCES drivers(id) ON DELETE SET NULL,
  total_pickups               INTEGER NOT NULL DEFAULT 1,
  total_distance_km           DOUBLE PRECISION,
  estimated_duration_minutes  INTEGER,
  base_pay                    DOUBLE PRECISION NOT NULL DEFAULT 0,
  distance_pay                DOUBLE PRECISION NOT NULL DEFAULT 0,
  extra_stop_pay              DOUBLE PRECISION NOT NULL DEFAULT 0,
  driver_earning              DOUBLE PRECISION NOT NULL DEFAULT 0,
  delivery_status             TEXT NOT NULL DEFAULT 'pending'
                                CHECK (delivery_status IN ('pending','assigned','in_progress','completed','cancelled')),
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT chk_task_parent CHECK (order_group_id IS NOT NULL OR order_id IS NOT NULL)
);

-- ── 4. delivery_stops  (pickup A → pickup B → dropoff) ───────
CREATE TABLE IF NOT EXISTS delivery_stops (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_task_id  UUID NOT NULL REFERENCES delivery_tasks(id) ON DELETE CASCADE,
  order_id          UUID REFERENCES orders(id) ON DELETE SET NULL,
  stop_type         TEXT NOT NULL CHECK (stop_type IN ('pickup','dropoff')),
  restaurant_id     UUID REFERENCES restaurants(id) ON DELETE SET NULL,
  sequence_number   INTEGER NOT NULL,
  address           TEXT,
  latitude          DOUBLE PRECISION,
  longitude         DOUBLE PRECISION,
  status            TEXT NOT NULL DEFAULT 'pending'
                      CHECK (status IN ('pending','arrived','completed')),
  arrived_at        TIMESTAMPTZ,
  completed_at      TIMESTAMPTZ
);

-- ── 5. Indexes ────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_order_group_id      ON orders(order_group_id);
CREATE INDEX IF NOT EXISTS idx_delivery_tasks_group        ON delivery_tasks(order_group_id);
CREATE INDEX IF NOT EXISTS idx_delivery_tasks_driver       ON delivery_tasks(driver_id);
CREATE INDEX IF NOT EXISTS idx_delivery_stops_task         ON delivery_stops(delivery_task_id);
CREATE INDEX IF NOT EXISTS idx_order_groups_customer       ON order_groups(customer_id);
CREATE INDEX IF NOT EXISTS idx_order_groups_payment_status ON order_groups(payment_status);

-- ── 6. Auto-update updated_at ─────────────────────────────────
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = NOW(); RETURN NEW; END;
$$;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_order_groups_updated_at') THEN
    CREATE TRIGGER trg_order_groups_updated_at
      BEFORE UPDATE ON order_groups
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'trg_delivery_tasks_updated_at') THEN
    CREATE TRIGGER trg_delivery_tasks_updated_at
      BEFORE UPDATE ON delivery_tasks
      FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
  END IF;
END $$;

-- ── 7. Admin config rows ──────────────────────────────────────
INSERT INTO app_config (key, value) VALUES
  ('enable_multi_restaurant_orders',   'true'),
  ('max_restaurants_per_order',        '2'),
  ('extra_stop_fee',                   '2.00'),
  ('max_restaurants_distance_km',      '8.0'),
  ('multi_restaurant_extra_minutes',   '15'),
  ('driver_extra_stop_pay',            '1.50')
ON CONFLICT (key) DO NOTHING;

-- ── 8. RLS ────────────────────────────────────────────────────
ALTER TABLE order_groups   ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_stops ENABLE ROW LEVEL SECURITY;

-- order_groups: customer sees own, admin sees all
CREATE POLICY "customer_own_order_group" ON order_groups
  FOR ALL USING (customer_id = auth.uid());

CREATE POLICY "admin_all_order_groups" ON order_groups
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );

-- delivery_tasks: driver sees assigned, admin sees all, customer sees via group
CREATE POLICY "driver_own_delivery_task" ON delivery_tasks
  FOR SELECT USING (
    driver_id IN (SELECT id FROM drivers WHERE user_id = auth.uid())
  );

CREATE POLICY "customer_delivery_task_via_group" ON delivery_tasks
  FOR SELECT USING (
    order_group_id IN (SELECT id FROM order_groups WHERE customer_id = auth.uid())
  );

CREATE POLICY "admin_all_delivery_tasks" ON delivery_tasks
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );

-- delivery_stops: driver sees stops on assigned task, customer sees via group
CREATE POLICY "driver_own_delivery_stops" ON delivery_stops
  FOR SELECT USING (
    delivery_task_id IN (
      SELECT id FROM delivery_tasks
      WHERE driver_id IN (SELECT id FROM drivers WHERE user_id = auth.uid())
    )
  );

CREATE POLICY "customer_delivery_stops_via_group" ON delivery_stops
  FOR SELECT USING (
    delivery_task_id IN (
      SELECT dt.id FROM delivery_tasks dt
      JOIN order_groups og ON og.id = dt.order_group_id
      WHERE og.customer_id = auth.uid()
    )
  );

CREATE POLICY "admin_all_delivery_stops" ON delivery_stops
  FOR ALL USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
