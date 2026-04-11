-- Migration 032: Notify admins and restaurants via FCM when a customer places an order
-- Uses pg_net to call the send-fcm-notification Edge Function

-- ── Admin notification: all new orders ──────────────────────────────────────

CREATE OR REPLACE FUNCTION public.notify_admin_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url  text := current_setting('app.settings.supabase_url', true);
  _service_key   text := current_setting('app.settings.service_role_key', true);
  _edge_url      text;
BEGIN
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';

  -- Only on INSERT (new order placed by customer)
  IF TG_OP = 'INSERT' THEN
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'admins',
        'title', 'New Order Placed! 🛒',
        'body',  'Order #' || NEW.id::text || ' has been placed by a customer.',
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

DROP TRIGGER IF EXISTS trg_notify_admin_new_order ON public.orders;

CREATE TRIGGER trg_notify_admin_new_order
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_admin_new_order();


-- ── Restaurant notification: order for their restaurant ─────────────────────

CREATE OR REPLACE FUNCTION public.notify_restaurant_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url  text := current_setting('app.settings.supabase_url', true);
  _service_key   text := current_setting('app.settings.service_role_key', true);
  _edge_url      text;
  _restaurant_name text;
BEGIN
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';

  -- Only on INSERT and when a restaurant_id is set
  IF TG_OP = 'INSERT' AND NEW.restaurant_id IS NOT NULL THEN
    -- Get the restaurant name for a nicer notification
    SELECT name INTO _restaurant_name
    FROM public.restaurants
    WHERE id = NEW.restaurant_id;

    -- Send to the specific restaurant topic (restaurant_{id})
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'restaurant_' || NEW.restaurant_id::text,
        'title', 'New Order Received! 🔔',
        'body',  'Order #' || NEW.id::text || ' has been placed' ||
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

    -- Also send to the broadcast topic so all restaurants see it
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'all_restaurants',
        'title', 'New Order on Platform! 📋',
        'body',  'Order #' || NEW.id::text || ' placed' ||
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

DROP TRIGGER IF EXISTS trg_notify_restaurant_new_order ON public.orders;

CREATE TRIGGER trg_notify_restaurant_new_order
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_restaurant_new_order();
