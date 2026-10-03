-- Restaurant Pickup Coordinator — start the one-line announcer the moment the
-- restaurant ANSWERS. When a pickup call's `calls` row flips to 'accepted', post
-- the "announce" action so the AI joins and speaks the message to a live line
-- (never into an empty channel). The service key lives in app_config
-- (automation_service_key), set out-of-band so it is never committed.
CREATE OR REPLACE FUNCTION public.pickup_on_call_answered()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE _ai uuid; _key text;
BEGIN
  IF NEW.status = 'accepted' AND COALESCE(OLD.status,'') <> 'accepted' THEN
    SELECT (value)::uuid INTO _ai FROM app_config WHERE key = 'pickup_ai_account_id';
    IF NEW.caller_id = _ai
       AND EXISTS (SELECT 1 FROM restaurant_pickup_calls c WHERE c.agora_call_id = NEW.id) THEN
      SELECT value INTO _key FROM app_config WHERE key = 'automation_service_key';
      IF _key IS NOT NULL THEN
        PERFORM extensions.http_post(
          url := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/restaurant-pickup-coordinator',
          body := jsonb_build_object('action','announce','agora_call_id', NEW.id)::text,
          headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||_key)
        );
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_pickup_on_answer ON public.calls;
CREATE TRIGGER trg_pickup_on_answer AFTER UPDATE ON public.calls
  FOR EACH ROW EXECUTE FUNCTION public.pickup_on_call_answered();

NOTIFY pgrst, 'reload schema';
