-- ============================================================================
-- Migration 108: Strict Payment Gating for Card Orders
-- ============================================================================
-- BUSINESS RULE: For card payments (payment_method IN ('stripe','card')),
-- an order MUST NOT be visible to restaurants or drivers, and MUST NOT
-- trigger any notifications, until payment_status = 'completed'.
--
-- Changes:
--   1. Expand orders.status CHECK  to include 'draft'
--   2. Expand orders.payment_status CHECK to include 'cancelled','processing'
--   3. Add checkout_status, payment_intent_id, finalized_at columns
--   4. DB-level payment gate trigger (cannot activate card order without payment)
--   5. Update notification triggers to respect payment status
--   6. Update driver RLS to exclude unpaid card orders
--   7. Update restaurant owner RLS to exclude unpaid card orders
-- ============================================================================

-- ── 1. Expand orders.status to include 'draft' ────────────────────────────────
-- 'draft' = order record created but card payment not yet confirmed.
-- The order is invisible to restaurants/drivers while in this state.

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_status_check CHECK (
  status IN (
    'draft',          -- card order created, awaiting payment
    'pending',        -- active order (payment confirmed or cash/wallet)
    'confirmed',
    'preparing',
    'ready',
    'picked_up',
    'on_the_way',
    'delivered',
    'cancelled'
  )
);

-- ── 2. Expand orders.payment_status ──────────────────────────────────────────
ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_payment_status_check;
ALTER TABLE public.orders ADD CONSTRAINT orders_payment_status_check CHECK (
  payment_status IN (
    'pending',      -- default; not yet charged
    'processing',   -- charge submitted, awaiting result
    'completed',    -- Stripe confirmed, webhook received
    'failed',       -- charge failed
    'cancelled',    -- customer cancelled before completion
    'refunded'      -- full refund issued
  )
);

-- ── 3. New columns ────────────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS checkout_status TEXT DEFAULT 'pending'
    CHECK (checkout_status IN (
      'draft', 'payment_pending', 'payment_processing',
      'payment_failed', 'payment_cancelled', 'payment_success',
      'pending', 'abandoned'
    )),
  ADD COLUMN IF NOT EXISTS payment_intent_id TEXT,
  ADD COLUMN IF NOT EXISTS finalized_at      TIMESTAMPTZ;

-- Unique index ensures a PaymentIntent can only finalize one order (idempotency).
CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_payment_intent_id
  ON public.orders (payment_intent_id)
  WHERE payment_intent_id IS NOT NULL;

-- ── 4. Database-level payment gate ────────────────────────────────────────────
-- Prevents card orders from becoming active without confirmed payment.
-- Service-role webhook is the ONLY path that sets both simultaneously.

CREATE OR REPLACE FUNCTION public.check_card_payment_gate()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Gate applies only to card payment methods
  IF NEW.payment_method IN ('stripe', 'card')
     AND NEW.status IN (
       'pending', 'confirmed', 'preparing', 'ready',
       'picked_up', 'on_the_way', 'delivered'
     )
     AND COALESCE(NEW.payment_status, 'pending') != 'completed'
  THEN
    RAISE EXCEPTION
      'PAYMENT_GATE: card order % cannot be activated (status=%) without payment_status=completed (current=%)',
      NEW.id, NEW.status, NEW.payment_status
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_card_payment_gate ON public.orders;
CREATE TRIGGER trg_card_payment_gate
  BEFORE INSERT OR UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.check_card_payment_gate();

-- ── 5a. Driver notification trigger — respect payment status ──────────────────
-- Fire driver notification only when:
--   a) Non-card INSERT as active order (cash/wallet immediate)
--   b) Card order: payment transitions to 'completed' (webhook fired)
--   c) Any order becomes 'ready' with no assigned driver

CREATE OR REPLACE FUNCTION public.notify_drivers_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url text := current_setting('app.settings.supabase_url', true);
  _service_key  text := current_setting('app.settings.service_role_key', true);
  _edge_url     text;
BEGIN
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';

  IF (
    -- Non-card order created directly as active (cash / wallet)
    (TG_OP = 'INSERT'
     AND NEW.driver_id IS NULL
     AND NEW.status IN ('pending', 'ready')
     AND NEW.payment_method NOT IN ('stripe', 'card')
     AND NEW.is_pickup IS NOT TRUE)
    OR
    -- Card order: payment just confirmed by webhook
    (TG_OP = 'UPDATE'
     AND NEW.payment_status = 'completed'
     AND OLD.payment_status IS DISTINCT FROM 'completed'
     AND NEW.driver_id IS NULL
     AND NEW.is_pickup IS NOT TRUE)
    OR
    -- Order became 'ready' with no driver (restaurant marked ready)
    (TG_OP = 'UPDATE'
     AND NEW.status = 'ready'
     AND OLD.status IS DISTINCT FROM 'ready'
     AND NEW.driver_id IS NULL
     AND NEW.payment_status = 'completed')
  ) THEN
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'available_drivers',
        'title', 'New Order Available! 🍔',
        'body',  'A new delivery order is waiting for pickup.',
        'data',  jsonb_build_object(
          'type',     'new_order',
          'order_id', NEW.id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || COALESCE(_service_key, '')
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_drivers_new_order ON public.orders;
CREATE TRIGGER trg_notify_drivers_new_order
  AFTER INSERT OR UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.notify_drivers_new_order();

-- ── 5b. Admin notification trigger ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_admin_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url text := current_setting('app.settings.supabase_url', true);
  _service_key  text := current_setting('app.settings.service_role_key', true);
  _edge_url     text;
BEGIN
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';

  IF (
    -- Non-card order: immediate INSERT as active
    (TG_OP = 'INSERT'
     AND NEW.status != 'draft'
     AND NEW.payment_method NOT IN ('stripe', 'card'))
    OR
    -- Card order: payment just confirmed
    (TG_OP = 'UPDATE'
     AND NEW.payment_status = 'completed'
     AND OLD.payment_status IS DISTINCT FROM 'completed')
  ) THEN
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'admins',
        'title', 'New Order Placed! 🛒',
        'body',  'Order #' || substring(NEW.id::text, 1, 8) || ' payment confirmed.',
        'data',  jsonb_build_object(
          'type',     'new_order_admin',
          'order_id', NEW.id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || COALESCE(_service_key, '')
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_admin_new_order ON public.orders;
CREATE TRIGGER trg_notify_admin_new_order
  AFTER INSERT OR UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.notify_admin_new_order();

-- ── 5c. Restaurant notification trigger ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.notify_restaurant_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url    text := current_setting('app.settings.supabase_url', true);
  _service_key     text := current_setting('app.settings.service_role_key', true);
  _edge_url        text;
  _restaurant_name text;
  _short_id        text;
BEGIN
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';

  IF (
    -- Non-card order: immediate INSERT as active
    (TG_OP = 'INSERT'
     AND NEW.status != 'draft'
     AND NEW.payment_method NOT IN ('stripe', 'card')
     AND NEW.restaurant_id IS NOT NULL)
    OR
    -- Card order: payment just confirmed
    (TG_OP = 'UPDATE'
     AND NEW.payment_status = 'completed'
     AND OLD.payment_status IS DISTINCT FROM 'completed'
     AND NEW.restaurant_id IS NOT NULL)
  ) THEN
    SELECT name INTO _restaurant_name
    FROM public.restaurants
    WHERE id = NEW.restaurant_id;

    _short_id := upper(substring(NEW.id::text, 1, 8));

    -- Notify the specific restaurant
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'restaurant_' || NEW.restaurant_id::text,
        'title', 'New Order Received! 🔔',
        'body',  'Order #' || _short_id || ' has been paid and is ready to prepare' ||
                 CASE WHEN _restaurant_name IS NOT NULL
                      THEN ' at ' || _restaurant_name ELSE '' END || '.',
        'data',  jsonb_build_object(
          'type',          'new_restaurant_order',
          'order_id',      NEW.id::text,
          'restaurant_id', NEW.restaurant_id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || COALESCE(_service_key, '')
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_restaurant_new_order ON public.orders;
CREATE TRIGGER trg_notify_restaurant_new_order
  AFTER INSERT OR UPDATE ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.notify_restaurant_new_order();

-- ── 6. Driver RLS: exclude unpaid card orders ─────────────────────────────────
-- Drivers must NEVER see a card order that hasn't been paid.

DROP POLICY IF EXISTS drivers_select_available_orders ON public.orders;
CREATE POLICY drivers_select_available_orders ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    driver_id IS NULL
    AND status IN ('pending', 'confirmed', 'preparing', 'ready')
    AND (payment_method NOT IN ('stripe', 'card') OR payment_status = 'completed')
    AND EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = auth.uid())
  );

-- ── 7. Restaurant owner RLS: exclude unpaid card orders ───────────────────────
-- Restaurant owners must NEVER see a card order that hasn't been paid.

DROP POLICY IF EXISTS "restaurant_owners_select_orders" ON public.orders;
CREATE POLICY "restaurant_owners_select_orders" ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.restaurants r
      WHERE r.id = orders.restaurant_id AND r.owner_id = auth.uid()
    )
    AND status != 'draft'
    AND (payment_method NOT IN ('stripe', 'card') OR payment_status = 'completed')
  );

-- ── 8. Index for fast draft-order queries (admin audit) ───────────────────────
CREATE INDEX IF NOT EXISTS idx_orders_draft_status
  ON public.orders (status, payment_method, ordered_at DESC)
  WHERE status = 'draft';
