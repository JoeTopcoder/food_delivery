-- Migration 098: Auto-insert notifications into the notifications table
-- when an order's status changes, so the customer's notifications screen
-- shows real order lifecycle updates.

CREATE OR REPLACE FUNCTION notify_customer_on_order_status_change()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
  _title TEXT;
  _body  TEXT;
  _type  TEXT;
BEGIN
  -- Only fire when status actually changes
  IF OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  CASE NEW.status
    WHEN 'confirmed' THEN
      _type  := 'order_confirmed';
      _title := '✅ Order Confirmed!';
      _body  := 'Your order #' || UPPER(SUBSTRING(NEW.id::text, 1, 8)) ||
                ' has been confirmed and is waiting to be prepared.';

    WHEN 'preparing' THEN
      _type  := 'preparing';
      _title := '👨‍🍳 Being Prepared';
      _body  := 'The restaurant is now preparing your order #' ||
                UPPER(SUBSTRING(NEW.id::text, 1, 8)) || '. Hang tight!';

    WHEN 'out_for_delivery' THEN
      _type  := 'out_for_delivery';
      _title := '🛵 Rider Assigned!';
      _body  := 'A rider has been assigned to your order #' ||
                UPPER(SUBSTRING(NEW.id::text, 1, 8)) ||
                ' and is on the way to you.';

    WHEN 'delivered' THEN
      _type  := 'delivered';
      _title := '🎉 Order Delivered!';
      _body  := 'Your order #' || UPPER(SUBSTRING(NEW.id::text, 1, 8)) ||
                ' has been successfully delivered. Thank you for using DashEats today!';

    WHEN 'cancelled' THEN
      _type  := 'order_cancelled';
      _title := '❌ Order Cancelled';
      _body  := 'Your order #' || UPPER(SUBSTRING(NEW.id::text, 1, 8)) ||
                ' has been cancelled. If you were charged, a refund is on its way.';

    ELSE
      RETURN NEW; -- No notification for other status values
  END CASE;

  INSERT INTO public.notifications (
    user_id,
    order_id,
    type,
    title,
    body,
    data,
    is_read,
    created_at
  ) VALUES (
    NEW.user_id,
    NEW.id,
    _type,
    _title,
    _body,
    jsonb_build_object('order_id', NEW.id, 'status', NEW.status),
    FALSE,
    NOW()
  );

  RETURN NEW;
END;
$$;

-- Drop old trigger if it exists then recreate
DROP TRIGGER IF EXISTS trg_order_status_notification ON public.orders;

CREATE TRIGGER trg_order_status_notification
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION notify_customer_on_order_status_change();

-- Also insert a notification when a new order is placed (INSERT)
CREATE OR REPLACE FUNCTION notify_customer_on_order_placed()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.notifications (
    user_id,
    order_id,
    type,
    title,
    body,
    data,
    is_read,
    created_at
  ) VALUES (
    NEW.user_id,
    NEW.id,
    'order_placed',
    '🍽️ Order Placed!',
    'Your order #' || UPPER(SUBSTRING(NEW.id::text, 1, 8)) ||
    ' has been placed successfully and is waiting for restaurant confirmation.',
    jsonb_build_object('order_id', NEW.id, 'status', 'pending'),
    FALSE,
    NOW()
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_placed_notification ON public.orders;

CREATE TRIGGER trg_order_placed_notification
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION notify_customer_on_order_placed();
