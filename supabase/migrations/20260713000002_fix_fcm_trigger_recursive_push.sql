-- ─────────────────────────────────────────────────────────────────────────────
-- CRITICAL FIX: send_fcm_on_notification_insert() could recurse indefinitely,
-- flooding a user with duplicate push notifications for a single event.
--
-- Root cause: this trigger builds its outgoing push data as
--   {type, notification_id, order_id} || NEW.data
-- — merging the ENTIRE notifications.data column into what it forwards to
-- send-fcm-notification. If the notification row's own `data` happened to
-- contain a `user_id` key (which it does whenever a caller used the
-- sendPushToCustomer()-style helper — see automation-workflow-runner and
-- ops-report-agent — to both push AND log an in-app row in one call),
-- send-fcm-notification's own logic ("if data.user_id present, also insert
-- into notifications") fires again on the trigger's own outbound call. That
-- insert fires this trigger again, still carrying user_id, forever.
--
-- Discovered 2026-08-31 when a birthday notification recursed to 200+ rows
-- for one customer before being caught and the trigger manually disabled as
-- an emergency stop. This bug was NOT specific to birthday notifications —
-- any notification whose `data` includes `user_id` could trigger it, so any
-- past use of the shared sendPushToCustomer() helper was equally at risk.
--
-- Fix: strip `user_id` from the merged data before forwarding — this
-- trigger's job is only ever to deliver a push for a row that already
-- exists; it must never cause send-fcm-notification to log a duplicate row.
-- ─────────────────────────────────────────────────────────────────────────────

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
  SELECT fcm_token INTO _fcm_token FROM public.users WHERE id = NEW.user_id;
  IF _fcm_token IS NULL OR _fcm_token = '' THEN
    RETURN NEW;
  END IF;

  _push_data := jsonb_build_object(
    'type',            NEW.type,
    'notification_id', NEW.id::text,
    'order_id',        COALESCE(NEW.order_id::text, '')
  );
  IF NEW.data IS NOT NULL THEN
    _push_data := _push_data || NEW.data;
  END IF;

  -- Critical: never forward user_id from here — see comment above.
  _push_data := _push_data - 'user_id';

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

-- Make sure the trigger is enabled — an earlier emergency response to this
-- bug disabled it manually via ALTER TABLE ... DISABLE TRIGGER while the
-- fix above was being written; this re-asserts the correct end state.
ALTER TABLE public.notifications ENABLE TRIGGER trg_notification_push_fcm;
