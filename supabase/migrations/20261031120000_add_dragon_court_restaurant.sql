-- Add Dragon Court Restaurant (Chinese; lunch/dinner), mirroring the other
-- manually-added partner restaurants (same owner, approved, cash payment).
BEGIN;
INSERT INTO restaurants (
  id, owner_id, name, description, cuisine_type, store_type,
  address, latitude, longitude,
  status, is_active, is_open, is_verified,
  rating, review_count, delivery_fee, minimum_order_amount, estimated_delivery_time,
  commission_rate, restaurant_payment_method, timezone,
  tags, operating_hours
) VALUES (
  '874e3bf5-d06f-4b85-b754-60be807b2a13', 'a0cb61a1-157e-4b62-854c-556f08edb8b9',
  'Dragon Court Restaurant',
  'Authentic Chinese cuisine for lunch and dinner.',
  'Chinese', 'food',
  '6 South Avenue, Kingston 10', 18.0125, -76.7930,
  'approved', true, true, true,
  4.1, 0, 0, 0, 35,
  0, 'CASH_PAYMENT', 'America/Jamaica',
  ARRAY['Chinese','Lunch','Dinner'],
  '{
    "sunday":    {"open":"11:30","close":"19:00","is_open":true},
    "monday":    {"open":"11:30","close":"19:00","is_open":true},
    "tuesday":   {"open":"11:30","close":"19:00","is_open":true},
    "wednesday": {"open":"11:30","close":"19:00","is_open":true},
    "thursday":  {"open":"11:30","close":"19:00","is_open":true},
    "friday":    {"open":"11:30","close":"19:00","is_open":true},
    "saturday":  {"open":"11:30","close":"19:00","is_open":true}
  }'::jsonb
);
NOTIFY pgrst, 'reload schema';
COMMIT;
