-- Migration 100: Fix FCM push trigger to use net.http_post (pg_net) instead of
-- the non-existent extensions.http_post signature.

CREATE OR REPLACE FUNCTION public.send_fcm_on_notification_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _fcm_token    text;
  _supabase_url text := 'https://yharweliruemjexmuuxn.supabase.co';
  _anon_key     text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InloYXJ3ZWxpcnVlbWpleG11dXhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0NDA1MTgsImV4cCI6MjA5MTAxNjUxOH0.etw9lBCZtWaJHPOiY6ozfFDEIMYcPQwG4hAah9whooA';
  _edge_url     text;
BEGIN
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
      'Authorization', 'Bearer ' || _anon_key
    )::jsonb
  );

  RETURN NEW;
END;
$$;
