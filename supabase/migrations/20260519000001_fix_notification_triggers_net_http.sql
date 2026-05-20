-- Migration: Fix notification triggers to use net.http_post (pg_net) instead of
-- the non-existent extensions.http_post.  Also wraps each PERFORM in an
-- exception block so a notification failure never aborts order creation.

-- ── notify_drivers_new_order (last defined in migration 110) ─────────────────
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
    (TG_OP = 'INSERT'
     AND NEW.driver_id IS NULL
     AND NEW.status IN ('pending', 'preparing', 'ready')
     AND NEW.payment_method NOT IN ('stripe', 'card')
     AND NEW.is_pickup IS NOT TRUE)
    OR
    (TG_OP = 'UPDATE'
     AND NEW.payment_status = 'completed'
     AND OLD.payment_status IS DISTINCT FROM 'completed'
     AND NEW.driver_id IS NULL
     AND NEW.is_pickup IS NOT TRUE)
    OR
    (TG_OP = 'UPDATE'
     AND NEW.status = 'ready'
     AND OLD.status IS DISTINCT FROM 'ready'
     AND NEW.driver_id IS NULL
     AND NEW.payment_status = 'completed')
  ) THEN
    BEGIN
      PERFORM net.http_post(
        url     := _edge_url,
        body    := jsonb_build_object(
          'topic', 'available_drivers',
          'title', 'New Order Available!',
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
    EXCEPTION WHEN OTHERS THEN
      -- Never let a notification failure abort order creation
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- ── notify_admin_new_order (defined in migration 108) ───────────────────────
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
    (TG_OP = 'INSERT'
     AND NEW.status != 'draft'
     AND NEW.payment_method NOT IN ('stripe', 'card'))
    OR
    (TG_OP = 'UPDATE'
     AND NEW.payment_status = 'completed'
     AND OLD.payment_status IS DISTINCT FROM 'completed')
  ) THEN
    BEGIN
      PERFORM net.http_post(
        url     := _edge_url,
        body    := jsonb_build_object(
          'topic', 'admins',
          'title', 'New Order Placed!',
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
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;

-- ── notify_restaurant_new_order (defined in migration 108) ──────────────────
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
    (TG_OP = 'INSERT'
     AND NEW.status != 'draft'
     AND NEW.payment_method NOT IN ('stripe', 'card')
     AND NEW.restaurant_id IS NOT NULL)
    OR
    (TG_OP = 'UPDATE'
     AND NEW.payment_status = 'completed'
     AND OLD.payment_status IS DISTINCT FROM 'completed'
     AND NEW.restaurant_id IS NOT NULL)
  ) THEN
    SELECT name INTO _restaurant_name
    FROM public.restaurants
    WHERE id = NEW.restaurant_id;

    _short_id := upper(substring(NEW.id::text, 1, 8));

    BEGIN
      PERFORM net.http_post(
        url     := _edge_url,
        body    := jsonb_build_object(
          'topic', 'restaurant_' || NEW.restaurant_id::text,
          'title', 'New Order Received!',
          'body',  'Order #' || _short_id || ' is ready to prepare' ||
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
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$$;
