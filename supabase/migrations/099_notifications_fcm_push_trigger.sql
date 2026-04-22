-- Migration 099: Send FCM push notification whenever a row is inserted
-- into the notifications table. This is the missing link between the DB
-- order-status trigger (098) and the device push notification.

CREATE OR REPLACE FUNCTION public.send_fcm_on_notification_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _fcm_token    text;
  _supabase_url text := current_setting('app.settings.supabase_url', true);
  _service_key  text := current_setting('app.settings.service_role_key', true);
  _edge_url     text;
BEGIN
  -- Fallback to hardcoded URL if pg config is missing
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';

  -- Look up the user's FCM token
  SELECT fcm_token INTO _fcm_token
  FROM public.users
  WHERE id = NEW.user_id;

  -- Skip if no token is registered for this user
  IF _fcm_token IS NULL OR _fcm_token = '' THEN
    RETURN NEW;
  END IF;

  -- Call the edge function to deliver the push via pg_net
  PERFORM net.http_post(
    url     := _edge_url,
    body    := jsonb_build_object(
      'token', _fcm_token,
      'title', NEW.title,
      'body',  COALESCE(NEW.body, ''),
      'data',  jsonb_build_object(
        'type',            NEW.type,
        'notification_id', NEW.id::text,
        'order_id',        COALESCE(NEW.order_id::text, '')
      )
    )::text,
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || COALESCE(
        _service_key,
        'sb_publishable_e-McqdkcLyoxV89A86lWGw_hD3vyVP6'
      )
    )::jsonb
  );

  RETURN NEW;
END;
$$;

-- Drop and recreate trigger
DROP TRIGGER IF EXISTS trg_notification_push_fcm ON public.notifications;

CREATE TRIGGER trg_notification_push_fcm
  AFTER INSERT ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.send_fcm_on_notification_insert();
