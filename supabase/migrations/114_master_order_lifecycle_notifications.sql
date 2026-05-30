-- =============================================================================
-- Migration 114: Exactly-once push notifications for multi-restaurant orders
--
-- Three events, one notification each:
--   1. ORDER PLACED   – INSERT into master_orders
--   2. ORDER DELIVERED – master_orders.status → 'delivered'
--   3. ORDER CANCELLED – master_orders.status → 'cancelled'
--      (partially_cancelled handled too, with a distinct message)
--
-- Each trigger inserts one row into the notifications table.
-- trg_notification_push_fcm (migration 099) then sends exactly one FCM push.
-- The data payload intentionally omits user_id so the send-fcm-notification
-- edge function does NOT re-insert into notifications (which would fire the
-- trigger again and double the push).
-- =============================================================================


-- ── 1. ORDER PLACED ───────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_notify_master_order_placed()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO notifications (user_id, type, title, body, data, is_read, created_at)
  VALUES (
    NEW.customer_id,
    'order_placed',
    '🍽️ Multi-Restaurant Order Placed!',
    'Your order #' || UPPER(LEFT(NEW.id::text, 8))
      || ' from ' || NEW.total_amount::text
      || ' has been placed and is waiting for the restaurants to confirm.',
    jsonb_build_object(
      'type',            'order_placed',
      'master_order_id', NEW.id::text,
      'status',          NEW.status
      -- no user_id → edge function skips notifications re-insert → no double push
    ),
    FALSE,
    NOW()
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_master_order_placed_notify ON master_orders;
CREATE TRIGGER trg_master_order_placed_notify
  AFTER INSERT ON master_orders
  FOR EACH ROW
  EXECUTE FUNCTION fn_notify_master_order_placed();


-- ── 2. ORDER DELIVERED ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_notify_master_order_delivered()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;
  IF NEW.status <> 'delivered' THEN RETURN NEW; END IF;

  INSERT INTO notifications (user_id, type, title, body, data, is_read, created_at)
  VALUES (
    NEW.customer_id,
    'delivered',
    '🎉 Order Delivered!',
    'Your multi-restaurant order #' || UPPER(LEFT(NEW.id::text, 8))
      || ' has been delivered. Enjoy your meal!',
    jsonb_build_object(
      'type',            'delivered',
      'master_order_id', NEW.id::text,
      'status',          'delivered'
    ),
    FALSE,
    NOW()
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_master_order_delivered_notify ON master_orders;
CREATE TRIGGER trg_master_order_delivered_notify
  AFTER UPDATE OF status ON master_orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered')
  EXECUTE FUNCTION fn_notify_master_order_delivered();


-- ── 3. ORDER CANCELLED / PARTIALLY CANCELLED ─────────────────────────────────
-- Replaces fn_notify_master_order_cancelled from migration 113 with an
-- improved version that also covers partially_cancelled separately.
CREATE OR REPLACE FUNCTION fn_notify_master_order_cancelled()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _title TEXT;
  _body  TEXT;
  _type  TEXT := 'order_cancelled';
BEGIN
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  CASE NEW.status
    WHEN 'cancelled' THEN
      _title := '❌ Order Cancelled';
      _body  := 'Your multi-restaurant order #' || UPPER(LEFT(NEW.id::text, 8))
                || ' has been cancelled.'
                || CASE WHEN NEW.payment_method IN ('stripe','card')
                        THEN ' A refund is on its way.'
                        ELSE ''
                   END;

    WHEN 'partially_cancelled' THEN
      _title := '⚠️ Order Partially Cancelled';
      _body  := 'One restaurant''s order was cancelled from #'
                || UPPER(LEFT(NEW.id::text, 8))
                || '. Other items are still being prepared.';

    ELSE RETURN NEW;
  END CASE;

  INSERT INTO notifications (user_id, type, title, body, data, is_read, created_at)
  VALUES (
    NEW.customer_id,
    _type,
    _title,
    _body,
    jsonb_build_object(
      'type',            _type,
      'master_order_id', NEW.id::text,
      'status',          NEW.status
    ),
    FALSE,
    NOW()
  );
  RETURN NEW;
END;
$$;

-- The trigger was already created by migration 113 — DROP + CREATE to pick up
-- the updated function body above.
DROP TRIGGER IF EXISTS trg_master_order_cancel_notify ON master_orders;
CREATE TRIGGER trg_master_order_cancel_notify
  AFTER UPDATE OF status ON master_orders
  FOR EACH ROW
  WHEN (
    NEW.status IN ('cancelled', 'partially_cancelled')
    AND OLD.status IS DISTINCT FROM NEW.status
  )
  EXECUTE FUNCTION fn_notify_master_order_cancelled();
