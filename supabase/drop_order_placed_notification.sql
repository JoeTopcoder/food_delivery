-- Drop the trigger that sends a push notification the moment an order is placed.
-- Customer will now only be notified once the restaurant confirms (status = 'confirmed').
DROP TRIGGER IF EXISTS trg_order_placed_notification ON public.orders;
