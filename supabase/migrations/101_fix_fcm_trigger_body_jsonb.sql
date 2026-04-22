-- Migration 101: Fix FCM trigger body type — net.http_post requires body as jsonb not text

CREATE OR REPLACE FUNCTION public.send_fcm_on_notification_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _fcm_token text;
  _edge_url  text := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/send-fcm-notification';
  _anon_key  text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InloYXJ3ZWxpcnVlbWpleG11dXhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0NDA1MTgsImV4cCI6MjA5MTAxNjUxOH0.etw9lBCZtWaJHPOiY6ozfFDEIMYcPQwG4hAah9whooA';
BEGIN
  -- Look up the user's FCM token
  SELECT fcm_token INTO _fcm_token
  FROM public.users
  WHERE id = NEW.user_id;

  -- Skip if no token registered
  IF _fcm_token IS NULL OR _fcm_token = '' THEN
    RETURN NEW;
  END IF;

  -- pg_net: body must be jsonb, headers must be jsonb
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
    ),
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || _anon_key
    )
  );

  RETURN NEW;
END;
$$;
