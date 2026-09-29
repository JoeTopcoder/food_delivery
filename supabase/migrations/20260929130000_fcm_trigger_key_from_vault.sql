-- ============================================================================
-- Move the FCM push trigger's edge-function key OUT of the function body and
-- into Supabase Vault, so the key is never a literal in SQL (or in git) again.
--
-- The key value was copied into Vault as the secret named 'fcm_edge_key'
-- (done out-of-band, server-side, so the value never touched a file). When you
-- ROTATE the anon key, you only update that one Vault secret — this function
-- needs no further change:
--
--   SELECT vault.update_secret(
--     (SELECT id FROM vault.secrets WHERE name='fcm_edge_key'),
--     '<new key>'
--   );
--
-- Behaviour is otherwise identical to the previous version (same recursion
-- guard that strips data.user_id before forwarding).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.send_fcm_on_notification_insert()
  RETURNS trigger
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path = public
AS $function$
DECLARE
  _fcm_token text;
  _edge_url  text := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/send-fcm-notification';
  _anon_key  text;
  _push_data jsonb;
BEGIN
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
