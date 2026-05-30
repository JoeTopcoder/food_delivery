-- Fix: restore body as jsonb (not text) and use the correct JWT anon key
-- Migration 101 proved net.http_post requires body as jsonb.
-- The 20260524000002 migration cast body to ::text which silently broke all pushes.

CREATE OR REPLACE FUNCTION public.send_fcm_on_notification_insert()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _fcm_token    text;
  _edge_url     text := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/send-fcm-notification';
  _anon_key     text := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InloYXJ3ZWxpcnVlbWpleG11dXhuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzU0NDA1MTgsImV4cCI6MjA5MTAxNjUxOH0.etw9lBCZtWaJHPOiY6ozfFDEIMYcPQwG4hAah9whooA';
  _push_data    jsonb;
BEGIN
  SELECT fcm_token INTO _fcm_token
  FROM public.users
  WHERE id = NEW.user_id;

  IF _fcm_token IS NULL OR _fcm_token = '' THEN
    RETURN NEW;
  END IF;

  -- Build base data, then merge extra fields (ride_id, booking_id, …)
  _push_data := jsonb_build_object(
    'type',            NEW.type,
    'notification_id', NEW.id::text,
    'order_id',        COALESCE(NEW.order_id::text, '')
  );
  IF NEW.data IS NOT NULL THEN
    _push_data := _push_data || NEW.data;
  END IF;

  -- body must be jsonb (NOT ::text) — pg_net requirement
  PERFORM net.http_post(
    url     := _edge_url,
    body    := jsonb_build_object(
      'token', _fcm_token,
      'title', NEW.title,
      'body',  COALESCE(NEW.body, ''),
      'data',  _push_data
    ),
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || _anon_key
    )
  );

  RETURN NEW;
END;
$$;
