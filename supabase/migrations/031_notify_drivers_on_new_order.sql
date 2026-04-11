-- Migration 031: Notify drivers via FCM when a new order becomes available
-- Uses pg_net to call the send-fcm-notification Edge Function

-- Enable pg_net extension (already available on Supabase hosted)
CREATE EXTENSION IF NOT EXISTS pg_net WITH SCHEMA extensions;

-- Function that fires an HTTP POST to the send-fcm-notification Edge Function
-- whenever an order becomes available for drivers (status → 'ready' and no driver assigned)
CREATE OR REPLACE FUNCTION public.notify_drivers_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url  text := current_setting('app.settings.supabase_url', true);
  _service_key   text := current_setting('app.settings.service_role_key', true);
  _edge_url      text;
BEGIN
  -- Fallback URL if setting is not available
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;

  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';

  -- Only fire when:
  --   INSERT with status ready/pending and no driver
  --   UPDATE where status changed to 'ready' and no driver
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
        'body',  'A new delivery order #' || NEW.id::text || ' is waiting for pickup.',
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

-- Drop trigger if it already exists (idempotent)
DROP TRIGGER IF EXISTS trg_notify_drivers_new_order ON public.orders;

-- Create trigger on orders table
CREATE TRIGGER trg_notify_drivers_new_order
  AFTER INSERT OR UPDATE ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_drivers_new_order();

-- Enable Realtime on orders table so the Flutter client gets live updates
ALTER PUBLICATION supabase_realtime ADD TABLE public.orders;
