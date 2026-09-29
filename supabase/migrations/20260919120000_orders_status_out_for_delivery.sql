-- Align orders.status CHECK constraint with the app's canonical value.
--
-- The app treats 'out_for_delivery' as the canonical "on the way" status
-- (AppConstants.orderOnTheWay, 49 usages across the Dart codebase), but the
-- live CHECK constraint only allowed the legacy 'on_the_way' — so the driver's
-- "Start Delivery" action failed with orders_status_check. This adds
-- 'out_for_delivery' while keeping 'on_the_way' for any legacy rows.

ALTER TABLE public.orders DROP CONSTRAINT IF EXISTS orders_status_check;

ALTER TABLE public.orders
  ADD CONSTRAINT orders_status_check
  CHECK (status = ANY (ARRAY[
    'draft'::text,
    'pending'::text,
    'confirmed'::text,
    'preparing'::text,
    'ready'::text,
    'picked_up'::text,
    'on_the_way'::text,
    'out_for_delivery'::text,
    'delivered'::text,
    'cancelled'::text
  ]));

NOTIFY pgrst, 'reload schema';
