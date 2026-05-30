-- =============================================================================
-- Migration 113: Single cancellation notification for multi-restaurant orders
--
-- Root cause of duplicate notifications:
--   Flutter _notifyCustomer() → send-fcm-notification edge function:
--     1. Sends FCM push
--     2. Inserts into notifications table (because data.user_id is set)
--   trg_notification_push_fcm (migration 099) fires on that INSERT:
--     3. Sends ANOTHER FCM push (loop stops because this call has no user_id)
--   Result: 2 device pushes per cancellation call.
--
-- Fix:
--   • Add a DB trigger on master_orders that inserts ONE notifications row
--     when status changes to cancelled or partially_cancelled.
--   • The existing trg_notification_push_fcm then delivers exactly 1 FCM push
--     (the pg_net call does NOT include user_id, so the edge function does not
--     re-insert — the loop stops after 1 round).
--   • Flutter cancel methods must NO LONGER call _notifyCustomer() themselves.
-- =============================================================================

CREATE OR REPLACE FUNCTION fn_notify_master_order_cancelled()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  _title TEXT;
  _body  TEXT;
  _type  TEXT := 'order_cancelled';
BEGIN
  -- Only fire when status actually changes
  IF OLD.status = NEW.status THEN RETURN NEW; END IF;

  CASE NEW.status
    WHEN 'cancelled' THEN
      _title := '❌ Order Cancelled';
      _body  := 'Your multi-restaurant order #'
                || UPPER(LEFT(NEW.id::text, 8))
                || ' has been cancelled.'
                || CASE WHEN NEW.payment_method IN ('stripe','card')
                        THEN ' A refund is on its way.'
                        ELSE ''
                   END;

    WHEN 'partially_cancelled' THEN
      _title := '⚠️ Order Partially Cancelled';
      _body  := 'One restaurant''s order was cancelled from your multi-restaurant '
                || 'order #' || UPPER(LEFT(NEW.id::text, 8))
                || '. Other items are still being prepared.';

    ELSE
      RETURN NEW; -- no notification for other statuses (handled elsewhere)
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
      -- Intentionally no user_id here: the edge function only re-inserts into
      -- notifications when data.user_id is present, which would cause a second
      -- push. Omitting it breaks the loop while still delivering 1 FCM push
      -- via the existing trg_notification_push_fcm trigger.
    ),
    FALSE,
    NOW()
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_master_order_cancel_notify ON master_orders;
CREATE TRIGGER trg_master_order_cancel_notify
  AFTER UPDATE OF status ON master_orders
  FOR EACH ROW
  WHEN (
    NEW.status IN ('cancelled', 'partially_cancelled')
    AND OLD.status IS DISTINCT FROM NEW.status
  )
  EXECUTE FUNCTION fn_notify_master_order_cancelled();
