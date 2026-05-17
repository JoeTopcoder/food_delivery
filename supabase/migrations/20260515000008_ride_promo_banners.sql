-- Ride promotional banner settings — editable by admin from the Rides Hub.
-- These drive the banner shown on the customer ride home screen.

INSERT INTO app_config (key, value, value_type, category, description)
VALUES
  -- First-ride banner (shown to new customers with no ride history)
  ('ride_promo_first_ride_enabled',  'true',                             'boolean', 'rides', 'Show the first-ride promo banner to new customers'),
  ('ride_promo_first_ride_title',    'First ride free!',                 'string',  'rides', 'Title on the first-ride banner'),
  ('ride_promo_first_ride_subtitle', 'Use code FIRSTRIDE at checkout',   'string',  'rides', 'Subtitle on the first-ride banner'),
  ('ride_promo_first_ride_code',     'FIRSTRIDE',                        'string',  'rides', 'Promo code shown on the first-ride banner'),
  ('ride_promo_first_ride_cta',      'Book now',                         'string',  'rides', 'Call-to-action button text on the first-ride banner'),

  -- Returning-rider banner (shown to customers who have already booked)
  ('ride_promo_returning_title',     'Ready for your next ride?',        'string',  'rides', 'Title on the returning-rider banner'),
  ('ride_promo_returning_subtitle',  'Fast, reliable rides at your fingertips', 'string', 'rides', 'Subtitle on the returning-rider banner'),
  ('ride_promo_returning_cta',       'Book a ride',                      'string',  'rides', 'Call-to-action button text on the returning-rider banner')

ON CONFLICT (key) DO NOTHING;
