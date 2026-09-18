-- Fix driver "new order" push: it targeted topic 'available_drivers' but drivers
-- subscribe to 'food_delivery_orders', used a stale auth key, and ignored the
-- payment/scheduled gating that decides whether an order is actually acceptable.
CREATE OR REPLACE FUNCTION public.notify_drivers_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url text := coalesce(
    nullif(current_setting('app.settings.supabase_url', true), ''),
    'https://yharweliruemjexmuuxn.supabase.co'
  );
  _key text := coalesce(
    nullif(current_setting('app.settings.service_role_key', true), ''),
    'sb_publishable_TSislwYLCUtwfkUnglQWBQ_3drsd82-'  -- current publishable key
  );
  _new_ok boolean;
  _old_ok boolean;
BEGIN
  -- An order is acceptable by a driver when it matches the driver-visibility
  -- rules: unassigned, an active status, paid if card, and not a scheduled
  -- order still held for later.
  _new_ok := NEW.driver_id IS NULL
    AND NEW.status IN ('pending','confirmed','preparing','ready')
    AND (NEW.payment_method NOT IN ('stripe','card') OR NEW.payment_status = 'completed')
    AND (NEW.scheduled_for IS NULL OR NEW.scheduled_for <= now() + interval '75 minutes');

  IF TG_OP = 'UPDATE' THEN
    _old_ok := OLD.driver_id IS NULL
      AND OLD.status IN ('pending','confirmed','preparing','ready')
      AND (OLD.payment_method NOT IN ('stripe','card') OR OLD.payment_status = 'completed')
      AND (OLD.scheduled_for IS NULL OR OLD.scheduled_for <= now() + interval '75 minutes');
  ELSE
    _old_ok := false;
  END IF;

  -- Only notify on the transition INTO an acceptable state (new insert that is
  -- already acceptable, or an update that just made it acceptable — e.g. a card
  -- payment completing). Prevents re-notifying on every unrelated update.
  IF _new_ok AND NOT _old_ok THEN
    PERFORM extensions.http_post(
      url  := _supabase_url || '/functions/v1/send-fcm-notification',
      body := jsonb_build_object(
        'topic', 'food_delivery_orders',
        'title', 'New Order Available',
        'body',  'A new delivery is ready to accept — open Orders to grab it.',
        'data',  jsonb_build_object(
          'type', 'new_order',
          'order_id', NEW.id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || _key
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

NOTIFY pgrst, 'reload schema';
