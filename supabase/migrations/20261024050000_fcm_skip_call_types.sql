-- Fix: admin→customer call pushed TWICE and the duplicate lingered after answer.
--
-- send-call-notification sends the real incoming-call push (high-priority,
-- data-only, drives CallKit), then ALSO logs a row into `notifications` for
-- history. That INSERT fires trg_notification_push_fcm -> send_fcm_on_notification_insert
-- -> a SECOND, generic FCM push. The generic one is an ordinary notification not
-- tied to the call lifecycle, so it kept notifying even after the customer
-- answered, and the double delivery added latency.
--
-- Make the FCM trigger SKIP call-type notifications: the dedicated call path
-- owns their delivery and cancellation. The history row is still written.
CREATE OR REPLACE FUNCTION public.send_fcm_on_notification_insert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  _fcm_token text;
  _edge_url  text := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/send-fcm-notification';
  _anon_key  text;
  _push_data jsonb;
BEGIN
  -- Call notifications are delivered by the dedicated send-call-notification /
  -- cancel-call-notification edge functions (CallKit). Do NOT send a second,
  -- generic push for the history row — that duplicate lingered after answering.
  IF NEW.type IN ('incoming_call','call_cancelled','call_accepted',
                  'call_ended','call_missed','call_declined') THEN
    RETURN NEW;
  END IF;

  -- Read the edge-function bearer key from Vault (never hardcoded here).
  SELECT decrypted_secret INTO _anon_key
  FROM vault.decrypted_secrets
  WHERE name = 'fcm_edge_key';

  IF _anon_key IS NULL OR _anon_key = '' THEN
    RAISE WARNING 'send_fcm_on_notification_insert: Vault secret fcm_edge_key missing; skipping push';
    RETURN NEW;
  END IF;

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
  -- Critical: strip user_id before forwarding. send-fcm-notification inserts
  -- a new notifications row whenever data.user_id is present — if that user_id
  -- survives into this trigger-originated call, the new insert fires this
  -- trigger again and recurses forever. This trigger only delivers a push for
  -- a row that already exists.
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
$function$;

NOTIFY pgrst, 'reload schema';
