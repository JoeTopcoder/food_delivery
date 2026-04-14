-- ============================================================
-- Migration 028: Feature Expansion
-- Scheduled orders, refunds/disputes, group orders,
-- subscriptions, surge pricing, post-delivery tips,
-- app feedback, cuisine categories, order receipts
-- ============================================================

-- ── 1. Scheduled Orders ─────────────────────────────────────
ALTER TABLE orders ADD COLUMN IF NOT EXISTS scheduled_for TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS is_scheduled BOOLEAN DEFAULT false;

-- ── 2. Refunds & Disputes ───────────────────────────────────
CREATE TABLE IF NOT EXISTS refunds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id),
  amount DECIMAL(10,2) NOT NULL,
  reason TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','rejected','processed')),
  admin_notes TEXT,
  refund_method TEXT DEFAULT 'original' CHECK (refund_method IN ('original','wallet','manual')),
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS disputes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id),
  type TEXT NOT NULL CHECK (type IN ('missing_item','wrong_item','quality','late_delivery','never_delivered','overcharged','other')),
  description TEXT NOT NULL,
  photo_urls TEXT[] DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open','investigating','resolved','closed')),
  resolution TEXT,
  resolved_by UUID REFERENCES users(id),
  refund_id UUID REFERENCES refunds(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ── 3. Group Orders ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS group_orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_user_id UUID NOT NULL REFERENCES users(id),
  restaurant_id UUID NOT NULL REFERENCES restaurants(id),
  name TEXT NOT NULL DEFAULT 'Group Order',
  invite_code TEXT UNIQUE NOT NULL,
  status TEXT NOT NULL DEFAULT 'collecting' CHECK (status IN ('collecting','locked','ordered','cancelled')),
  deadline TIMESTAMPTZ,
  delivery_address TEXT,
  delivery_latitude DOUBLE PRECISION,
  delivery_longitude DOUBLE PRECISION,
  order_id UUID REFERENCES orders(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS group_order_participants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_order_id UUID NOT NULL REFERENCES group_orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id),
  items JSONB NOT NULL DEFAULT '[]',
  subtotal DECIMAL(10,2) DEFAULT 0,
  is_paid BOOLEAN DEFAULT false,
  joined_at TIMESTAMPTZ DEFAULT now()
);

-- ── 4. Subscriptions / Meal Plans ───────────────────────────
CREATE TABLE IF NOT EXISTS meal_plans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  description TEXT,
  restaurant_id UUID REFERENCES restaurants(id),
  price DECIMAL(10,2) NOT NULL,
  frequency TEXT NOT NULL CHECK (frequency IN ('daily','weekly','monthly')),
  meals_per_period INT NOT NULL DEFAULT 1,
  items JSONB NOT NULL DEFAULT '[]',
  is_active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  meal_plan_id UUID NOT NULL REFERENCES meal_plans(id),
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active','paused','cancelled','expired')),
  start_date DATE NOT NULL,
  next_delivery DATE,
  delivery_address TEXT,
  delivery_latitude DOUBLE PRECISION,
  delivery_longitude DOUBLE PRECISION,
  meals_remaining INT DEFAULT 0,
  auto_renew BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- ── 5. Surge Pricing ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS surge_zones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  radius_km DOUBLE PRECISION NOT NULL DEFAULT 5.0,
  multiplier DOUBLE PRECISION NOT NULL DEFAULT 1.0,
  is_active BOOLEAN DEFAULT false,
  reason TEXT,
  starts_at TIMESTAMPTZ DEFAULT now(),
  ends_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ── 6. Post-Delivery Tips ───────────────────────────────────
ALTER TABLE orders ADD COLUMN IF NOT EXISTS post_delivery_tip DECIMAL(10,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS tip_updated_at TIMESTAMPTZ;

-- ── 7. App Feedback ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS app_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id),
  type TEXT NOT NULL CHECK (type IN ('bug','feature','compliment','complaint','other')),
  message TEXT NOT NULL,
  rating INT CHECK (rating >= 1 AND rating <= 5),
  app_version TEXT,
  device_info TEXT,
  screenshot_url TEXT,
  status TEXT DEFAULT 'new' CHECK (status IN ('new','reviewed','in_progress','resolved','wont_fix')),
  admin_response TEXT,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ── 8. Cuisine Categories ───────────────────────────────────
CREATE TABLE IF NOT EXISTS cuisine_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT UNIQUE NOT NULL,
  icon_name TEXT,
  display_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT true
);

-- Seed categories
INSERT INTO cuisine_categories (name, icon_name, display_order) VALUES
  ('Caribbean', 'restaurant', 1),
  ('Jamaican', 'local_dining', 2),
  ('Indian', 'curry', 3),
  ('Chinese', 'ramen_dining', 4),
  ('Italian', 'local_pizza', 5),
  ('American', 'fastfood', 6),
  ('Japanese', 'set_meal', 7),
  ('Mexican', 'takeout_dining', 8),
  ('Thai', 'rice_bowl', 9),
  ('Breakfast', 'free_breakfast', 10),
  ('Desserts', 'cake', 11),
  ('Seafood', 'lunch_dining', 12),
  ('Vegetarian', 'eco', 13),
  ('Fast Food', 'fastfood', 14),
  ('Healthy', 'spa', 15)
ON CONFLICT (name) DO NOTHING;

-- ── 9. Order Receipts ───────────────────────────────────────
ALTER TABLE orders ADD COLUMN IF NOT EXISTS receipt_number TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS receipt_generated_at TIMESTAMPTZ;

-- Generate receipt number trigger
CREATE OR REPLACE FUNCTION generate_receipt_number()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'delivered' AND OLD.status != 'delivered' AND NEW.receipt_number IS NULL THEN
    NEW.receipt_number := 'FD-' || TO_CHAR(now(), 'YYYYMMDD') || '-' || LPAD(
      (SELECT COUNT(*) + 1 FROM orders WHERE DATE(ordered_at) = CURRENT_DATE AND receipt_number IS NOT NULL)::TEXT,
      4, '0'
    );
    NEW.receipt_generated_at := now();
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_receipt_number ON orders;
CREATE TRIGGER trg_receipt_number
  BEFORE UPDATE ON orders
  FOR EACH ROW
  EXECUTE FUNCTION generate_receipt_number();

-- ── 10. ETA tracking ────────────────────────────────────────
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_delivery_at TIMESTAMPTZ;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_prep_minutes INT;

-- ── 11. Driver location history (for route tracking) ────────
CREATE TABLE IF NOT EXISTS driver_location_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES drivers(id),
  order_id UUID REFERENCES orders(id),
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  speed DOUBLE PRECISION,
  heading DOUBLE PRECISION,
  recorded_at TIMESTAMPTZ DEFAULT now()
);

-- Index for fast location queries
CREATE INDEX IF NOT EXISTS idx_driver_location_history_driver 
  ON driver_location_history(driver_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_driver_location_history_order 
  ON driver_location_history(order_id, recorded_at DESC);

-- ── RLS Policies ────────────────────────────────────────────
ALTER TABLE refunds ENABLE ROW LEVEL SECURITY;
ALTER TABLE disputes ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE group_order_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE meal_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE surge_zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE app_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE cuisine_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE driver_location_history ENABLE ROW LEVEL SECURITY;

-- Refunds: users see own, admins see all
CREATE POLICY refunds_select ON refunds FOR SELECT USING (
  user_id = auth.uid() OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY refunds_insert ON refunds FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY refunds_update ON refunds FOR UPDATE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- Disputes: users see own, admins see all
CREATE POLICY disputes_select ON disputes FOR SELECT USING (
  user_id = auth.uid() OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY disputes_insert ON disputes FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY disputes_update ON disputes FOR UPDATE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- Group orders: participants + host
CREATE POLICY group_orders_select ON group_orders FOR SELECT USING (
  host_user_id = auth.uid() OR EXISTS (
    SELECT 1 FROM group_order_participants WHERE group_order_id = id AND user_id = auth.uid()
  )
);
CREATE POLICY group_orders_insert ON group_orders FOR INSERT WITH CHECK (host_user_id = auth.uid());
CREATE POLICY group_orders_update ON group_orders FOR UPDATE USING (host_user_id = auth.uid());

CREATE POLICY group_participants_select ON group_order_participants FOR SELECT USING (
  user_id = auth.uid() OR EXISTS (
    SELECT 1 FROM group_orders WHERE id = group_order_id AND host_user_id = auth.uid()
  )
);
CREATE POLICY group_participants_insert ON group_order_participants FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY group_participants_update ON group_order_participants FOR UPDATE USING (user_id = auth.uid());

-- Meal plans: public read
CREATE POLICY meal_plans_select ON meal_plans FOR SELECT USING (true);
CREATE POLICY meal_plans_admin ON meal_plans FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role IN ('admin','restaurant'))
);

-- User subscriptions: own only
CREATE POLICY subscriptions_select ON user_subscriptions FOR SELECT USING (user_id = auth.uid());
CREATE POLICY subscriptions_insert ON user_subscriptions FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY subscriptions_update ON user_subscriptions FOR UPDATE USING (user_id = auth.uid());

-- Surge zones: public read, admin write
CREATE POLICY surge_zones_select ON surge_zones FOR SELECT USING (true);
CREATE POLICY surge_zones_admin ON surge_zones FOR ALL USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- App feedback: own insert + view, admin sees all
CREATE POLICY feedback_select ON app_feedback FOR SELECT USING (
  user_id = auth.uid() OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY feedback_insert ON app_feedback FOR INSERT WITH CHECK (user_id = auth.uid());
CREATE POLICY feedback_update ON app_feedback FOR UPDATE USING (
  EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
);

-- Cuisine categories: public read
CREATE POLICY cuisine_categories_select ON cuisine_categories FOR SELECT USING (true);

-- Driver location history
CREATE POLICY driver_location_insert ON driver_location_history FOR INSERT WITH CHECK (
  EXISTS (SELECT 1 FROM drivers WHERE id = driver_id AND user_id = auth.uid())
);
CREATE POLICY driver_location_select ON driver_location_history FOR SELECT USING (true);

-- ── App config additions ────────────────────────────────────
INSERT INTO app_config (key, value, value_type, category, description) VALUES
  ('surge_base_multiplier', '1.0', 'number', 'surge', 'Base surge multiplier'),
  ('surge_high_demand_threshold', '10', 'number', 'surge', 'Orders per hour to trigger surge'),
  ('surge_max_multiplier', '2.5', 'number', 'surge', 'Maximum surge multiplier'),
  ('default_prep_minutes', '25', 'number', 'orders', 'Default prep time in minutes'),
  ('post_tip_window_hours', '24', 'number', 'tips', 'Hours after delivery user can tip'),
  ('group_order_max_participants', '10', 'number', 'group_orders', 'Max participants in group order'),
  ('group_order_deadline_minutes', '60', 'number', 'group_orders', 'Default deadline for group orders'),
  ('subscription_trial_days', '7', 'number', 'subscriptions', 'Free trial period'),
  ('receipt_company_name', 'FoodHub Jamaica', 'string', 'receipts', 'Company name on receipts'),
  ('receipt_company_address', 'Kingston, Jamaica', 'string', 'receipts', 'Company address on receipts'),
  ('receipt_company_trn', '', 'string', 'receipts', 'Tax registration number'),
  ('eta_buffer_minutes', '10', 'number', 'orders', 'Extra buffer minutes for ETA'),
  ('driver_location_interval_seconds', '10', 'number', 'drivers', 'GPS update interval')
ON CONFLICT (key) DO NOTHING;
