-- supabase-migrate-no-transaction
-- ═══════════════════════════════════════════════════════════════════════════
-- Performance indexes for 7M+ user scale
-- All created so they don't lock production tables.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── orders ──────────────────────────────────────────────────────────────────
-- Customer active-order lookup (most frequent query in the app)
CREATE INDEX IF NOT EXISTS idx_orders_user_active
  ON public.orders (user_id, created_at DESC)
  WHERE status NOT IN ('delivered', 'cancelled');

-- Driver active-delivery lookup
CREATE INDEX IF NOT EXISTS idx_orders_driver_active
  ON public.orders (driver_id, created_at DESC)
  WHERE status NOT IN ('delivered', 'cancelled');

-- Restaurant order queue (pending/confirmed/preparing)
CREATE INDEX IF NOT EXISTS idx_orders_restaurant_queue
  ON public.orders (restaurant_id, created_at DESC)
  WHERE status IN ('pending', 'confirmed', 'preparing', 'ready');

-- Status-only index for admin dashboards / reporting
CREATE INDEX IF NOT EXISTS idx_orders_status_created
  ON public.orders (status, created_at DESC);

-- Full customer order history (order history screen pagination)
CREATE INDEX IF NOT EXISTS idx_orders_user_history
  ON public.orders (user_id, created_at DESC);

-- ── users ────────────────────────────────────────────────────────────────────
-- Role-based lookups (login routing, admin user lists)
CREATE INDEX IF NOT EXISTS idx_users_role
  ON public.users (role);

-- Phone lookup for OTP / auth
CREATE INDEX IF NOT EXISTS idx_users_phone
  ON public.users (phone)
  WHERE phone IS NOT NULL;

-- FCM token lookup for push notifications
CREATE INDEX IF NOT EXISTS idx_users_fcm_token
  ON public.users (fcm_token)
  WHERE fcm_token IS NOT NULL;

-- ── drivers ───────────────────────────────────────────────────────────────────
-- user_id → driver lookup (used on every authenticated driver request)
CREATE INDEX IF NOT EXISTS idx_drivers_user_id
  ON public.drivers (user_id);

-- Available driver pool (location-based dispatch)
CREATE INDEX IF NOT EXISTS idx_drivers_available
  ON public.drivers (is_available, is_active)
  WHERE is_available = true AND is_active = true;

-- ── restaurants ───────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_restaurants_owner
  ON public.restaurants (owner_id);

CREATE INDEX IF NOT EXISTS idx_restaurants_active
  ON public.restaurants (created_at DESC);

-- ── order_items ───────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_order_items_order_id
  ON public.order_items (order_id);

-- ── notifications ─────────────────────────────────────────────────────────────
-- Unread notification count (badge)
CREATE INDEX IF NOT EXISTS idx_notifications_user_unread
  ON public.notifications (user_id, created_at DESC)
  WHERE is_read = false;

-- Full notification history
CREATE INDEX IF NOT EXISTS idx_notifications_user_created
  ON public.notifications (user_id, created_at DESC);

-- ── chat / messages ───────────────────────────────────────────────────────────
-- Conversation message load (newest first)
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
  ON public.chat_messages (conversation_id, created_at DESC);

-- Unread message detection
CREATE INDEX IF NOT EXISTS idx_messages_unread
  ON public.chat_messages (conversation_id, is_read)
  WHERE is_read = false;

-- ── reviews ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_reviews_restaurant
  ON public.reviews (restaurant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reviews_driver
  ON public.reviews (driver_id, created_at DESC)
  WHERE driver_id IS NOT NULL;

-- ── wallet_transactions ───────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_wallet_tx_user_created
  ON public.wallet_transactions (user_id, created_at DESC);

-- ── menu_items ────────────────────────────────────────────────────────────────
-- Restaurant menu load
CREATE INDEX IF NOT EXISTS idx_menu_items_restaurant
  ON public.menu_items (restaurant_id);

-- ── ai_voice_sessions ─────────────────────────────────────────────────────────
-- Already indexed in migration 20260424000001, this is a no-op safety guard
CREATE INDEX IF NOT EXISTS idx_ai_voice_sessions_created
  ON public.ai_voice_sessions (user_id, created_at DESC);
