-- Migration: let an admin close a support chat.
--
-- "Closed" is derived from closed_at rather than stored as a status string, so
-- there is one source of truth and no way for a status column and a timestamp
-- to disagree about the same conversation.
--
-- A closed chat is not a locked chat. If the customer writes again, the
-- conversation reopens itself — see the trigger at the bottom. Closing is the
-- admin saying "this is handled", not the platform refusing to listen.

ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS closed_at    TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS closed_by    UUID REFERENCES public.users(id),
  ADD COLUMN IF NOT EXISTS close_reason TEXT;

-- The admin list is "open chats, newest first", which is this index exactly.
CREATE INDEX IF NOT EXISTS conversations_open_idx
  ON public.conversations (last_message_at DESC)
  WHERE closed_at IS NULL;

-- ── Close ───────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_close_conversation(
  p_conversation_id UUID,
  p_reason          TEXT DEFAULT NULL
)
RETURNS TABLE (
  id           UUID,
  closed_at    TIMESTAMPTZ,
  closed_by    UUID,
  close_reason TEXT
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_admin UUID := auth.uid();
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  IF p_conversation_id IS NULL THEN
    RAISE EXCEPTION 'A conversation id is required';
  END IF;

  -- Trim to NULL so an empty reason is stored as absent rather than as an
  -- empty string the UI would have to special-case.
  p_reason := NULLIF(btrim(COALESCE(p_reason, '')), '');
  IF length(p_reason) > 500 THEN
    RAISE EXCEPTION 'Reason is too long (max 500 characters)';
  END IF;

  RETURN QUERY
  UPDATE public.conversations c
     SET closed_at    = COALESCE(c.closed_at, now()),  -- closing twice keeps
         closed_by    = COALESCE(c.closed_by, v_admin), -- the first close
         close_reason = COALESCE(c.close_reason, p_reason),
         updated_at   = now()
   WHERE c.id = p_conversation_id
  RETURNING c.id, c.closed_at, c.closed_by, c.close_reason;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No conversation with id %', p_conversation_id;
  END IF;
END;
$fn$;

-- ── Reopen ──────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_reopen_conversation(
  p_conversation_id UUID
)
RETURNS TABLE (id UUID, closed_at TIMESTAMPTZ)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  IF p_conversation_id IS NULL THEN
    RAISE EXCEPTION 'A conversation id is required';
  END IF;

  RETURN QUERY
  UPDATE public.conversations c
     SET closed_at    = NULL,
         closed_by    = NULL,
         close_reason = NULL,
         updated_at   = now()
   WHERE c.id = p_conversation_id
  RETURNING c.id, c.closed_at;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'No conversation with id %', p_conversation_id;
  END IF;
END;
$fn$;

-- ── A customer writing again reopens the chat ───────────────────────────────
-- Without this, closing would silently mute someone: they reply, nobody sees
-- it, and the chat stays out of the admin queue forever. Only messages from
-- someone other than an admin reopen it, so an admin adding a closing note
-- does not undo their own close.
CREATE OR REPLACE FUNCTION public.reopen_conversation_on_reply()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF COALESCE(NEW.sender_role, '') = 'admin' THEN
    RETURN NULL;
  END IF;

  IF NEW.conversation_id IS NOT NULL THEN
    UPDATE public.conversations
       SET closed_at = NULL, closed_by = NULL, close_reason = NULL,
           updated_at = now()
     WHERE id = NEW.conversation_id AND closed_at IS NOT NULL;
  ELSIF NEW.order_id IS NOT NULL THEN
    -- Older messages carry only order_id. Every current row has both, but the
    -- column is nullable and the fallback costs nothing.
    UPDATE public.conversations
       SET closed_at = NULL, closed_by = NULL, close_reason = NULL,
           updated_at = now()
     WHERE order_id = NEW.order_id AND closed_at IS NOT NULL;
  END IF;

  RETURN NULL;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_reopen_conversation_on_reply ON public.chat_messages;
CREATE TRIGGER trg_reopen_conversation_on_reply
  AFTER INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.reopen_conversation_on_reply();

-- PUBLIC holds the default EXECUTE grant and anon inherits it, so revoking
-- anon alone would change nothing.
DO $grants$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('admin_close_conversation', 'admin_reopen_conversation')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END
$grants$;

NOTIFY pgrst, 'reload schema';
