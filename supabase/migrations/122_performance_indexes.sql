-- ── 122_performance_indexes ─────────────────────────────────────────────────
-- Adds targeted indexes for every high-traffic query pattern found during the
-- Artillery load test (849k requests, p95 = 2.3s).
--
-- IMPORTANT: CREATE INDEX CONCURRENTLY cannot run inside a transaction block.
-- Supabase migrations run inside a transaction by default, so we use plain
-- CREATE INDEX … IF NOT EXISTS.  If the table is large and you need to avoid
-- locking, run the statements manually in the Supabase SQL editor using the
-- CONCURRENTLY keyword after the initial migration has created the column.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── orders ───────────────────────────────────────────────────────────────────

-- Driver picks up available orders: WHERE status = 'confirmed' AND driver_id IS NULL
CREATE INDEX IF NOT EXISTS idx_orders_status_driver
  ON public.orders (status, driver_id);

-- Customer order history: WHERE user_id = $1 ORDER BY ordered_at DESC
CREATE INDEX IF NOT EXISTS idx_orders_user_created
  ON public.orders (user_id, ordered_at DESC);

-- Restaurant dashboard — orders for this restaurant ordered recently
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_created
  ON public.orders (restaurant_id, ordered_at DESC);

-- Admin/analytics — orders by status over time
CREATE INDEX IF NOT EXISTS idx_orders_status_created
  ON public.orders (status, ordered_at DESC);

-- ── restaurants ──────────────────────────────────────────────────────────────

-- Home screen browse: WHERE is_open = true AND is_verified = true ORDER BY rating DESC
-- Partial index keeps it tiny (only open/verified rows included).
CREATE INDEX IF NOT EXISTS idx_restaurants_open_verified_rating
  ON public.restaurants (rating DESC)
  WHERE is_open = TRUE AND is_verified = TRUE;

-- Category/cuisine filter: WHERE cuisine_type = $1 AND is_open = true
CREATE INDEX IF NOT EXISTS idx_restaurants_cuisine_open
  ON public.restaurants (cuisine_type, is_open);

-- Store-type filter used to separate food from grocery
CREATE INDEX IF NOT EXISTS idx_restaurants_store_type_open
  ON public.restaurants (store_type, is_open);

-- Full-text search fallback — speeds up ILIKE name/cuisine queries
CREATE INDEX IF NOT EXISTS idx_restaurants_name_trgm
  ON public.restaurants USING gin (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_restaurants_cuisine_trgm
  ON public.restaurants USING gin (cuisine_type gin_trgm_ops);

-- ── menu_items (menus table) ─────────────────────────────────────────────────

-- Restaurant detail screen — available items for this restaurant
CREATE INDEX IF NOT EXISTS idx_menus_restaurant_available
  ON public.menus (restaurant_id, is_available);

-- Category browse across all restaurants
CREATE INDEX IF NOT EXISTS idx_menus_category_available
  ON public.menus (category, is_available);

-- ── drivers ──────────────────────────────────────────────────────────────────

-- Finding available/online drivers
CREATE INDEX IF NOT EXISTS idx_drivers_available_online
  ON public.drivers (is_available, is_online)
  WHERE is_available = TRUE;

-- Driver location queries (bounding-box spatial lookups)
CREATE INDEX IF NOT EXISTS idx_drivers_location
  ON public.drivers (current_lat, current_lng);

-- ── notifications ─────────────────────────────────────────────────────────────

-- User notification bell: WHERE user_id = $1 ORDER BY created_at DESC
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON public.notifications (user_id, created_at DESC);

-- Unread badge count: WHERE user_id = $1 AND is_read = false
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON public.notifications (user_id, is_read)
  WHERE is_read = FALSE;

-- ── reviews ──────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_reviews_restaurant_created
  ON public.reviews (restaurant_id, created_at DESC);

-- ── order_items ──────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_order_items_order
  ON public.order_items (order_id);

-- ── payments ─────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_payments_user_created
  ON public.payments (user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_payments_order
  ON public.payments (order_id);

-- ── master_orders (group orders) ─────────────────────────────────────────────

-- Only create these if the master_orders table exists in this deployment.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'master_orders') THEN

    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_master_orders_customer_created
             ON public.master_orders (customer_id, created_at DESC)';

    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_master_orders_status_created
             ON public.master_orders (status, created_at DESC)';
  END IF;
END $$;

-- ── ride_requests ─────────────────────────────────────────────────────────────

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema = 'public' AND table_name = 'ride_requests') THEN

    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_ride_requests_status_driver
             ON public.ride_requests (status, driver_id)';

    EXECUTE 'CREATE INDEX IF NOT EXISTS idx_ride_requests_customer_created
             ON public.ride_requests (customer_id, created_at DESC)';
  END IF;
END $$;

-- Enable pg_trgm extension required for gin_trgm_ops indexes above.
-- Safe to run even if already enabled.
CREATE EXTENSION IF NOT EXISTS pg_trgm;
