-- New-order push refinement: only when the order becomes READY, and only to
-- active drivers within ~3 km of the store. The proximity/availability filtering
-- happens in the notify-nearby-drivers edge function (a trigger can't loop over
-- per-driver sends); this trigger just fires it on the ready transition.
CREATE OR REPLACE FUNCTION public.notify_drivers_new_order()
RETURNS trigger
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
  _ready_now boolean;
  _was_ready boolean;
BEGIN
  -- Acceptable & READY: unassigned, status 'ready', card orders must be paid,
  -- and a scheduled order must be within its release window.
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
    PERFORM extensions.http_post(
      url  := _url || '/functions/v1/notify-nearby-drivers',
      body := jsonb_build_object('order_id', NEW.id::text)::text,
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
