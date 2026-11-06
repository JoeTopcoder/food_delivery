-- Add Potwah Diner & Bar (Jamaican; breakfast/lunch/dinner), mirroring the setup
-- of other manually-added partner restaurants (same owner, approved, cash payment).
BEGIN;
INSERT INTO restaurants (
  id, owner_id, name, description, cuisine_type, store_type,
  address, latitude, longitude,
  status, is_active, is_open, is_verified,
  rating, review_count, delivery_fee, minimum_order_amount, estimated_delivery_time,
  commission_rate, restaurant_payment_method, timezone,
  tags, operating_hours
) VALUES (
  '2a614cb0-9eb6-4af4-bb8e-71d95a84fe6c', 'a0cb61a1-157e-4b62-854c-556f08edb8b9',
  'Potwah Diner & Bar',
  'If yuh luv Potwah, cum nyam wid we. Authentic Jamaican breakfast, lunch and dinner.',
  'Jamaican', 'food',
  '8 Hillview Ave, Kingston 10, Kingston', 18.0180, -76.7940,
  'approved', true, true, true,
  4.5, 0, 0, 0, 35,
  0, 'CASH_PAYMENT', 'America/Jamaica',
  ARRAY['Jamaican','Breakfast','Lunch','Dinner'],
  '{
    "sunday":    {"open":"10:00","close":"15:00","is_open":true},
    "monday":    {"open":"10:00","close":"17:00","is_open":true},
    "tuesday":   {"open":"10:00","close":"17:00","is_open":true},
    "wednesday": {"open":"10:00","close":"17:00","is_open":true},
    "thursday":  {"open":"10:00","close":"17:00","is_open":true},
    "friday":    {"open":"10:00","close":"17:00","is_open":true},
    "saturday":  {"open":"10:00","close":"17:00","is_open":true}
  }'::jsonb
);
NOTIFY pgrst, 'reload schema';
COMMIT;
