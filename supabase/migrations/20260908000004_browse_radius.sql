-- Migration: hide stores the customer is too far from to order from.
--
-- The catalogue still holds 34 Cayman Islands restaurants from the app's
-- previous life, 370-490 km from Kingston. A Jamaican customer was browsing a
-- menu they could never be delivered — which is most of what an empty-looking,
-- unusable app costs you.
--
-- This is the browse limit, and it is NOT the same as delivery_max_km, which is
-- what actually refuses an order at checkout. Setting this ABOVE that one puts
-- stores in front of customers that will reject them at payment, so the two
-- want to move together.

INSERT INTO public.app_config (key, value, value_type, description)
VALUES ('browse_max_km', '50', 'number',
        'Max km from the customer a store may be and still be listed. Keep at or below delivery_max_km.')
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value,
      value_type = 'number',
      description = EXCLUDED.description;

NOTIFY pgrst, 'reload schema';
