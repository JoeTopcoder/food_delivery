-- Migration 036: Fix order notification messages to use short uppercase order ID
-- Changes full UUID to first 8 chars (uppercase) in all notification bodies

-- ── Driver notification ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_drivers_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url  text := current_setting('app.settings.supabase_url', true);
  _service_key   text := current_setting('app.settings.service_role_key', true);
  _edge_url      text;
  _short_id      text;
BEGIN
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';
  _short_id := UPPER(LEFT(NEW.id::text, 8));

  IF (
    (TG_OP = 'INSERT' AND NEW.driver_id IS NULL AND NEW.status IN ('ready', 'pending'))
    OR
    (TG_OP = 'UPDATE' AND NEW.status = 'ready' AND (OLD.status IS DISTINCT FROM 'ready') AND NEW.driver_id IS NULL)
  ) THEN
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'available_drivers',
        'title', 'New Order Available! 🍔',
        'body',  'A new delivery order #' || _short_id || ' is waiting for pickup.',
        'data',  jsonb_build_object(
          'type',     'new_order',
          'order_id', NEW.id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || COALESCE(_service_key, 'sb_publishable_e-McqdkcLyoxV89A86lWGw_hD3vyVP6')
      )
    );
  END IF;

  RETURN NEW;
END;
$$;


-- ── Admin notification ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_admin_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url  text := current_setting('app.settings.supabase_url', true);
  _service_key   text := current_setting('app.settings.service_role_key', true);
  _edge_url      text;
  _short_id      text;
BEGIN
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url  := _supabase_url || '/functions/v1/send-fcm-notification';
  _short_id  := UPPER(LEFT(NEW.id::text, 8));

  -- Only on INSERT (new order placed by customer)
  IF TG_OP = 'INSERT' THEN
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'admins',
        'title', 'New Order Placed! 🛒',
        'body',  'Order #' || _short_id || ' has been placed by a customer.',
        'data',  jsonb_build_object(
          'type',     'new_order_admin',
          'order_id', NEW.id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || COALESCE(_service_key, 'sb_publishable_e-McqdkcLyoxV89A86lWGw_hD3vyVP6')
      )
    );
  END IF;

  RETURN NEW;
END;
$$;


-- ── Restaurant notification ──────────────────────────────────────────────────

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
  _short_id := UPPER(LEFT(NEW.id::text, 8));

  -- Only on INSERT and when a restaurant_id is set
  IF TG_OP = 'INSERT' AND NEW.restaurant_id IS NOT NULL THEN
    -- Get the restaurant name for a nicer notification
    SELECT name INTO _restaurant_name
    FROM public.restaurants
    WHERE id = NEW.restaurant_id;

    -- Send to the specific restaurant topic
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'restaurant_' || NEW.restaurant_id::text,
        'title', 'New Order Received! 🔔',
        'body',  'Order #' || _short_id || ' has been placed' ||
                 CASE WHEN _restaurant_name IS NOT NULL
                      THEN ' at ' || _restaurant_name
                      ELSE '' END || '.',
        'data',  jsonb_build_object(
          'type',          'new_restaurant_order',
          'order_id',      NEW.id::text,
          'restaurant_id', NEW.restaurant_id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || COALESCE(_service_key, 'sb_publishable_e-McqdkcLyoxV89A86lWGw_hD3vyVP6')
      )
    );

    -- Also send to broadcast topic
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'all_restaurants',
        'title', 'New Order on Platform! 📋',
        'body',  'Order #' || _short_id || ' placed' ||
                 CASE WHEN _restaurant_name IS NOT NULL
                      THEN ' at ' || _restaurant_name
                      ELSE '' END || '.',
        'data',  jsonb_build_object(
          'type',          'new_restaurant_order',
          'order_id',      NEW.id::text,
          'restaurant_id', NEW.restaurant_id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || COALESCE(_service_key, 'sb_publishable_e-McqdkcLyoxV89A86lWGw_hD3vyVP6')
      )
    );
  END IF;

  RETURN NEW;
END;
$$;
