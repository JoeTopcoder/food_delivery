-- CRITICAL FIX: notify_drivers_new_order and remind_stores_mark_ready called
-- extensions.http_post with a TEXT body, which does not exist — so the driver
-- trigger raised and ROLLED BACK the store's "mark ready" update, and the store
-- reminder cron silently failed. The real function is net.http_post(url, body
-- jsonb, params jsonb, headers jsonb, timeout int). Body must be jsonb.

CREATE OR REPLACE FUNCTION public.notify_drivers_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _url text := coalesce(nullif(current_setting('app.settings.supabase_url', true), ''), 'https://yharweliruemjexmuuxn.supabase.co');
  _key text := coalesce(nullif(current_setting('app.settings.service_role_key', true), ''), 'sb_publishable_TSislwYLCUtwfkUnglQWBQ_3drsd82-');
  _ready_now boolean;
  _was_ready boolean;
BEGIN
  _ready_now := NEW.driver_id IS NULL
    AND NEW.status = 'ready'
    AND (NEW.payment_method NOT IN ('stripe','card') OR NEW.payment_status = 'completed')
    AND (NEW.scheduled_for IS NULL OR NEW.scheduled_for <= now() + interval '75 minutes');

  IF TG_OP = 'UPDATE' THEN
    _was_ready := OLD.driver_id IS NULL
      AND OLD.status = 'ready'
      AND (OLD.payment_method NOT IN ('stripe','card') OR OLD.payment_status = 'completed')
      AND (OLD.scheduled_for IS NULL OR OLD.scheduled_for <= now() + interval '75 minutes');
  ELSE
    _was_ready := false;
  END IF;

  IF _ready_now AND NOT _was_ready THEN
    -- Best-effort: never let a notification failure roll back the order update.
    BEGIN
      PERFORM net.http_post(
        url     := _url || '/functions/v1/notify-nearby-drivers',
        body    := jsonb_build_object('order_id', NEW.id::text),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || _key
        )
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'notify_drivers_new_order push failed: %', SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.remind_stores_mark_ready()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _url text := coalesce(nullif(current_setting('app.settings.supabase_url', true), ''), 'https://yharweliruemjexmuuxn.supabase.co');
  _key text := coalesce(nullif(current_setting('app.settings.service_role_key', true), ''), 'sb_publishable_TSislwYLCUtwfkUnglQWBQ_3drsd82-');
  _rec record;
BEGIN
  FOR _rec IN
    SELECT o.id, r.owner_id
    FROM orders o JOIN restaurants r ON r.id = o.restaurant_id
    WHERE o.status IN ('pending','confirmed','preparing')
      AND (o.payment_method NOT IN ('stripe','card') OR o.payment_status = 'completed')
      AND (o.scheduled_for IS NULL OR o.scheduled_for <= now() + interval '75 minutes')
      AND o.created_at >= now() - interval '2 hours'
      AND coalesce(o.last_ready_reminder_at, o.created_at) <= now() - interval '8 minutes'
      AND r.owner_id IS NOT NULL
    LIMIT 200
  LOOP
    BEGIN
      PERFORM net.http_post(
        url     := _url || '/functions/v1/send-fcm-notification',
        body    := jsonb_build_object(
          'topic', 'restaurant_' || _rec.owner_id::text,
          'title', 'Order waiting — mark it Ready',
          'body',  'An order still needs to be marked Ready for pickup. Open Orders to update it.',
          'data',  jsonb_build_object('type', 'mark_ready_reminder', 'order_id', _rec.id::text)
        ),
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'Authorization', 'Bearer ' || _key
        )
      );
      UPDATE orders SET last_ready_reminder_at = now() WHERE id = _rec.id;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'remind_stores_mark_ready push failed for %: %', _rec.id, SQLERRM;
    END;
  END LOOP;
END;
$$;

NOTIFY pgrst, 'reload schema';
