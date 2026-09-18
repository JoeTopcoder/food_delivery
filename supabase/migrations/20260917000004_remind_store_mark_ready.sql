-- Nudge the store to mark an order READY: every 8 minutes while an order is
-- placed-but-not-ready, push the store owner. Stops automatically once the
-- order leaves the un-ready statuses (marked ready / delivered / cancelled).

ALTER TABLE orders ADD COLUMN IF NOT EXISTS last_ready_reminder_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_orders_ready_reminder
  ON orders (status, last_ready_reminder_at)
  WHERE status IN ('pending', 'confirmed', 'preparing');

CREATE OR REPLACE FUNCTION public.remind_stores_mark_ready()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _url text := coalesce(
    nullif(current_setting('app.settings.supabase_url', true), ''),
    'https://yharweliruemjexmuuxn.supabase.co'
  );
  _key text := coalesce(
    nullif(current_setting('app.settings.service_role_key', true), ''),
    'sb_publishable_TSislwYLCUtwfkUnglQWBQ_3drsd82-'
  );
  _rec record;
BEGIN
  FOR _rec IN
    SELECT o.id, r.owner_id, r.name AS store_name
    FROM orders o
    JOIN restaurants r ON r.id = o.restaurant_id
    WHERE o.status IN ('pending', 'confirmed', 'preparing')
      AND (o.payment_method NOT IN ('stripe', 'card') OR o.payment_status = 'completed')
      AND (o.scheduled_for IS NULL OR o.scheduled_for <= now() + interval '75 minutes')
      AND o.created_at >= now() - interval '2 hours'          -- don't nag ancient stuck orders
      AND coalesce(o.last_ready_reminder_at, o.created_at) <= now() - interval '8 minutes'
      AND r.owner_id IS NOT NULL
    LIMIT 200
  LOOP
    PERFORM extensions.http_post(
      url  := _url || '/functions/v1/send-fcm-notification',
      body := jsonb_build_object(
        'topic', 'restaurant_' || _rec.owner_id::text,
        'title', 'Order waiting — mark it Ready',
        'body',  'An order still needs to be marked Ready for pickup. Open Orders to update it.',
        'data',  jsonb_build_object('type', 'mark_ready_reminder', 'order_id', _rec.id::text)
      )::text,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || _key
      )
    );
    UPDATE orders SET last_ready_reminder_at = now() WHERE id = _rec.id;
  END LOOP;
END;
$$;

-- Run every 2 minutes; the 8-minute spacing is enforced inside the function.
SELECT cron.unschedule('remind-stores-mark-ready')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'remind-stores-mark-ready');
SELECT cron.schedule('remind-stores-mark-ready', '*/2 * * * *',
  $$ SELECT public.remind_stores_mark_ready(); $$);

NOTIFY pgrst, 'reload schema';
