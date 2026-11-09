-- Restaurants could not Accept / change an order's status: the status-change
-- customer notification trigger (notify_customer_on_order_status_change) ran as
-- SECURITY INVOKER and INSERTed into public.notifications for the CUSTOMER
-- (NEW.user_id). A restaurant owner is not permitted by notifications RLS to
-- insert a row for another user, so the INSERT raised
--   42501 new row violates row-level security policy for table "notifications"
-- which aborted the whole UPDATE and surfaced in-app as
--   "You don't have permission to do that..."
--
-- Every sibling notify_* order trigger is already SECURITY DEFINER. Make this
-- one DEFINER too so the notification is written on the function owner's
-- authority, regardless of which party (restaurant / driver / customer) changed
-- the status. The function still only ever notifies the order's own customer.
BEGIN;

ALTER FUNCTION public.notify_customer_on_order_status_change()
  SECURITY DEFINER;

-- Keep a hardened search_path (defence-in-depth for SECURITY DEFINER).
ALTER FUNCTION public.notify_customer_on_order_status_change()
  SET search_path = public, extensions, pg_temp;

COMMIT;

NOTIFY pgrst, 'reload schema';
