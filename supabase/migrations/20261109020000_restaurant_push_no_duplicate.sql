-- The previous version sent BOTH a device-token push AND a topic push, so a
-- restaurant with a known token received TWO notifications per order. Send to
-- the device TOKEN when we have one, and fall back to the TOPIC only when we
-- don't — exactly one notification per order.
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

    BEGIN
      IF _owner_token IS NOT NULL AND _owner_token <> '' THEN
        -- Reliable device-token send (preferred). One notification.
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
      ELSE
        -- No stored token yet: fall back to the topic.
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
      END IF;
    EXCEPTION WHEN OTHERS THEN
      NULL;
    END;
  END IF;

  RETURN NEW;
END;
$function$;

NOTIFY pgrst, 'reload schema';
