-- ── 124_additional_performance_indexes ───────────────────────────────────────
-- Adds the indexes from the Task-5 performance spec that are NOT already
-- covered by migration 122.
--
-- What 122 already has (no duplicates here):
--   idx_orders_status_driver           ON orders(status, driver_id)
--   idx_orders_user_created            ON orders(user_id, ordered_at DESC)
--   idx_restaurants_open_verified_rating  partial ON restaurants(rating DESC)
--   idx_menus_restaurant_available     ON menus(restaurant_id, is_available)
--   idx_notifications_user_created     ON notifications(user_id, created_at DESC)
--
-- New indexes added below:
--   1. idx_orders_user_created_at    — complementary to ordered_at; some queries
--                                      filter/sort by created_at instead.
--   2. idx_restaurants_open_rating   — non-partial composite; the partial in 122
--                                      excludes rows where is_verified=false.
--                                      Some admin/owner queries don't add is_verified.
--   3. idx_menus_restaurant_category — for category-filtered menu browsing
--                                      (GET /menus?category=eq.X&restaurant_id=eq.Y)
--   4. idx_users_role_active         — for role-filtered user lists (admin dashboard)
-- ─────────────────────────────────────────────────────────────────────────────

-- Orders: complementary index on created_at (122 has ordered_at)
CREATE INDEX IF NOT EXISTS idx_orders_user_created_at
  ON public.orders (user_id, created_at DESC);

-- Restaurants: non-partial open+rating (useful for queries without is_verified)
CREATE INDEX IF NOT EXISTS idx_restaurants_open_rating
  ON public.restaurants (is_open, rating DESC);

-- Menus: category browsing within a restaurant
CREATE INDEX IF NOT EXISTS idx_menus_restaurant_category
  ON public.menus (restaurant_id, category, is_available);

-- Users: role + active filter used by admin dashboard
CREATE INDEX IF NOT EXISTS idx_users_role_active
  ON public.users (role, is_active);
