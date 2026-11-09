-- Restaurant new-order push was delivered only via FCM TOPIC
-- (`restaurant_<restaurant_id>`). Topic fan-out is eventually-consistent and
-- unreliable (recently-subscribed devices routinely miss messages), which is why
-- restaurants frequently got no alert when an order was placed. Customer/driver
-- notifications use the device TOKEN directly (immediate, reliable).
--
-- Rewrite notify_restaurant_new_order to send to the owner's device TOKEN first
-- (one per owner) and ALSO to the topic as a backup. Both calls are wrapped so a
-- failure in one never blocks the order insert/update.
CREATE OR REPLACE FUNCTION public.notify_restaurant_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  _supabase_url    text := current_setting('app.settings.supabase_url', true);
  _service_key     text := current_setting('app.settings.service_role_key', true);
  _edge_url        text;
  _restaurant_name text;
  _short_id        text;
  _owner_token     text;
  _title           text;
  _body            text;
  _data            jsonb;
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
    SELECT r.name, u.fcm_token
      INTO _restaurant_name, _owner_token
    FROM public.restaurants r
    LEFT JOIN public.users u ON u.id = r.owner_id
    WHERE r.id = NEW.restaurant_id;

    _short_id := upper(left(NEW.id::text,8));
    _title := 'New Order Received!';
    _body  := 'Order #' || _short_id || ' is ready to prepare' ||
              CASE WHEN _restaurant_name IS NOT NULL
                   THEN ' at ' || _restaurant_name ELSE '' END || '.';
    _data  := jsonb_build_object(
      'type',          'new_restaurant_order',
      'order_id',      NEW.id::text,
      'restaurant_id', NEW.restaurant_id::text
    );

    -- 1) Direct device-token send (reliable). Only if the owner has a token.
    IF _owner_token IS NOT NULL AND _owner_token <> '' THEN
      BEGIN
        PERFORM net.http_post(
          url     := _edge_url,
          body    := jsonb_build_object(
            'token', _owner_token,
            'title', _title,
            'body',  _body,
            'data',  _data
          ),
          headers := jsonb_build_object(
            'Content-Type',  'application/json',
            'Authorization', 'Bearer ' || COALESCE(_service_key, '')
          )
        );
      EXCEPTION WHEN OTHERS THEN
        NULL;
      END;
    END IF;

    -- 2) Topic send (backup; also covers multiple devices / owners not yet
    --    token-refreshed on this build).
    BEGIN
      PERFORM net.http_post(
        url     := _edge_url,
        body    := jsonb_build_object(
          'topic', 'restaurant_' || NEW.restaurant_id::text,
          'title', _title,
          'body',  _body,
          'data',  _data
        ),
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
$function$;

NOTIFY pgrst, 'reload schema';
