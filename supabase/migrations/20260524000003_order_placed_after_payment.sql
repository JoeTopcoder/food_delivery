-- Send "order placed" push only after payment is confirmed.
-- Card/Stripe: fires when payment_status transitions to 'completed'.
-- Cash/wallet: fires on INSERT (no gateway, order is immediately live).

CREATE OR REPLACE FUNCTION public.notify_customer_on_order_placed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _user_id uuid;
BEGIN
  -- Determine which user to notify
  _user_id := NEW.user_id;

  -- INSERT path: only for non-card payment methods (cash, wallet, etc.)
  IF TG_OP = 'INSERT' THEN
    IF NEW.payment_method IN ('stripe', 'card') THEN
      RETURN NEW; -- card orders wait for payment webhook
    END IF;
  END IF;

  -- UPDATE path: only when payment_status just became 'completed'
  IF TG_OP = 'UPDATE' THEN
    IF NOT (NEW.payment_status = 'completed'
            AND OLD.payment_status IS DISTINCT FROM 'completed') THEN
      RETURN NEW;
    END IF;
  END IF;

  INSERT INTO public.notifications (
    user_id,
    type,
    title,
    body,
    order_id,
    data
  ) VALUES (
    _user_id,
    'order_placed',
    '🎉 Order Placed!',
    'Your order has been received and is waiting for the restaurant to confirm.',
    NEW.id,
    jsonb_build_object('order_id', NEW.id::text, 'status', NEW.status)
  );

  RETURN NEW;
END;
$$;

-- Fire on INSERT (cash/wallet) and on UPDATE (card payment confirmed)
DROP TRIGGER IF EXISTS trg_order_placed_notification ON public.orders;
CREATE TRIGGER trg_order_placed_notification
AFTER INSERT OR UPDATE OF payment_status ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.notify_customer_on_order_placed();
