-- Reliable admin notification on every new order.
--
-- The previous notify_admin_new_order() pushed to the FCM *topic* 'admins' using
-- a service_role_key GUC that is EMPTY on this project (so the call sent an empty
-- Bearer and failed silently). It also depended on admins being subscribed to the
-- topic, and never populated the in-app notifications bell.
--
-- New approach: on order placement, INSERT one notifications row per admin. The
-- existing send_fcm_on_notification_insert trigger then delivers a direct
-- per-user FCM push to each admin's device (using their users.fcm_token) AND the
-- row shows in the admin app's notifications list. No topic subscription, no
-- empty-key dependency. No recursion: that push trigger strips data.user_id, and
-- send-fcm-notification only re-inserts a row when data.user_id is present.
CREATE OR REPLACE FUNCTION public.notify_admin_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
BEGIN
  -- Fire once, at placement (INSERT), for any real (non-draft) order — whatever
  -- the payment method, so admins are alerted the moment a customer orders.
  IF TG_OP = 'INSERT' AND COALESCE(NEW.status,'') <> 'draft' THEN
    INSERT INTO public.notifications (user_id, order_id, type, title, body, data)
    SELECT u.id,
           NEW.id,
           'new_order_admin',
           'New order placed',
           'Order #' || substring(NEW.id::text, 1, 8)
             || ' — JMD ' || to_char(COALESCE(NEW.total_amount,0), 'FM999999990.00')
             || ' · ' || COALESCE(NEW.payment_method, 'payment'),
           jsonb_build_object('type', 'new_order_admin', 'order_id', NEW.id::text)
    FROM public.users u
    WHERE u.role = 'admin';
  END IF;
  RETURN NEW;
END;
$fn$;

NOTIFY pgrst, 'reload schema';
