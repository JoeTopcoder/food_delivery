-- Migration: WhatsApp order updates, via an outbox.
--
-- Jamaica is a WhatsApp market. Push needs the app installed, permission
-- granted and the phone not asleep in battery saver; WhatsApp gets read. There
-- is no WhatsApp anywhere in this codebase today — support_whatsapp is still
-- the string 'TODO_CONFIGURE'.
--
-- Messages are QUEUED here rather than sent from the trigger. Three reasons:
--
--   Nothing is lost before credentials exist. No provider is configured yet;
--   rows sit as 'queued' and go out the moment one is, instead of the feature
--   silently doing nothing until someone remembers to backfill.
--
--   An outbound HTTP call inside a trigger makes order status changes depend
--   on a third party being up. Placing an order should not fail because
--   WhatsApp is slow.
--
--   It is auditable and retryable. A push that vanished is unprovable; a row
--   with an attempt count and the provider's error is not. This codebase has
--   already had a push trigger recurse and send one user 200+ duplicates —
--   this one writes to a different table than it reads, so it cannot recurse.

CREATE TABLE IF NOT EXISTS public.whatsapp_outbox (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID REFERENCES public.users(id) ON DELETE SET NULL,
  order_id     UUID REFERENCES public.orders(id) ON DELETE CASCADE,
  to_phone     TEXT NOT NULL,
  body         TEXT NOT NULL,
  -- The milestone this message is for; also what makes it deduplicable.
  event        TEXT NOT NULL,
  status       TEXT NOT NULL DEFAULT 'queued'
               CHECK (status IN ('queued','sent','failed','skipped')),
  attempts     INT  NOT NULL DEFAULT 0,
  last_error   TEXT,
  provider_id  TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  sent_at      TIMESTAMPTZ
);

-- One message per order per milestone, however many times a status is written.
-- Order rows get touched by several triggers and by admin edits; a customer
-- should not get "your rider is on the way" three times.
CREATE UNIQUE INDEX IF NOT EXISTS idx_whatsapp_outbox_once
  ON public.whatsapp_outbox (order_id, event);

CREATE INDEX IF NOT EXISTS idx_whatsapp_outbox_queued
  ON public.whatsapp_outbox (created_at) WHERE status = 'queued';

ALTER TABLE public.whatsapp_outbox ENABLE ROW LEVEL SECURITY;
-- Customers may see their own messages; the queue is otherwise service-role.
DROP POLICY IF EXISTS whatsapp_outbox_own ON public.whatsapp_outbox;
CREATE POLICY whatsapp_outbox_own ON public.whatsapp_outbox
  FOR SELECT USING (user_id = auth.uid());

-- ── Enqueue on the milestones worth interrupting someone for ───────────────
-- Deliberately not every status. WhatsApp is intrusive and metered; "confirmed"
-- and "preparing" back to back is how a customer mutes you.
CREATE OR REPLACE FUNCTION public.enqueue_whatsapp_order_update()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_phone TEXT;
  v_name  TEXT;
  v_ref   TEXT;
  v_body  TEXT;
  v_event TEXT;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;

  v_event := NEW.status;
  -- 'on_the_way', not 'out_for_delivery'. orders_status_check permits
  -- draft/pending/confirmed/preparing/ready/picked_up/on_the_way/delivered/
  -- cancelled, and nothing else — a branch on 'out_for_delivery' is dead code
  -- that never fires. (notify_customer_on_order_status_change has exactly that
  -- branch for its "Rider Assigned!" push.)
  IF v_event NOT IN ('on_the_way', 'delivered', 'cancelled') THEN
    RETURN NEW;
  END IF;

  SELECT u.phone, split_part(COALESCE(u.name, ''), ' ', 1)
    INTO v_phone, v_name
  FROM public.users u WHERE u.id = NEW.user_id;

  -- No number, nothing to send. Not an error: most accounts have no phone.
  IF v_phone IS NULL OR btrim(v_phone) = '' THEN
    RETURN NEW;
  END IF;

  v_ref := COALESCE(NEW.receipt_number, UPPER(LEFT(NEW.id::text, 8)));

  v_body := CASE v_event
    WHEN 'on_the_way' THEN
      COALESCE(NULLIF(v_name,'') || ', y', 'Y') ||
      'our QuickDash order ' || v_ref || ' is on the way. ' ||
      'Track it in the app.'
    WHEN 'delivered' THEN
      COALESCE(NULLIF(v_name,'') || ', y', 'Y') ||
      'our QuickDash order ' || v_ref || ' has been delivered. ' ||
      'Enjoy! Rate your driver in the app.'
    WHEN 'cancelled' THEN
      COALESCE(NULLIF(v_name,'') || ', y', 'Y') ||
      'our QuickDash order ' || v_ref || ' was cancelled. ' ||
      'Any payment is being returned to your wallet.'
  END;

  INSERT INTO public.whatsapp_outbox (user_id, order_id, to_phone, body, event)
  VALUES (NEW.user_id, NEW.id, btrim(v_phone), v_body, v_event)
  ON CONFLICT (order_id, event) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_whatsapp_order_update ON public.orders;
CREATE TRIGGER trg_whatsapp_order_update
AFTER UPDATE OF status ON public.orders
FOR EACH ROW EXECUTE FUNCTION public.enqueue_whatsapp_order_update();

NOTIFY pgrst, 'reload schema';
