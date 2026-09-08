-- Migration: measure from Kingston when the customer's location is unknown.
--
-- The browse filter previously gave up when it had no customer coordinates and
-- showed the whole catalogue — which on a Jamaican launch means showing the 34
-- Cayman restaurants left over from the app's previous life. A brand-new
-- account, or one that refused location, saw exactly the wrong thing.
--
-- It now measures from here instead, so a customer with no address sees the
-- same Kingston list a Kingston customer sees. Move these if the launch city
-- moves; no rebuild needed.

INSERT INTO public.app_config (key, value, value_type, description) VALUES
  ('default_origin_lat', '18.0179', 'number',
   'Latitude to measure store distance from when the customer has no address (Kingston)'),
  ('default_origin_lng', '-76.8099', 'number',
   'Longitude to measure store distance from when the customer has no address (Kingston)')
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value,
      value_type = 'number',
      description = EXCLUDED.description;

-- Browsing wider than we will deliver puts stores in front of customers that
-- reject them at checkout. delivery_max_km is 25, so this matches it.
UPDATE public.app_config SET value = '25' WHERE key = 'browse_max_km';

NOTIFY pgrst, 'reload schema';
