-- Add Dragon Garden Restaurant (Chinese; lunch/dinner/drinks), mirroring the
-- other manually-added partner restaurants (same owner, approved, cash payment).
BEGIN;
INSERT INTO restaurants (
  id, owner_id, name, description, cuisine_type, store_type,
  address, latitude, longitude,
  status, is_active, is_open, is_verified,
  rating, review_count, delivery_fee, minimum_order_amount, estimated_delivery_time,
  commission_rate, restaurant_payment_method, timezone,
  tags, operating_hours
) VALUES (
  '7361796c-518d-4619-9ac2-2d15e98d4af8', 'a0cb61a1-157e-4b62-854c-556f08edb8b9',
  'Dragon Garden Restaurant',
  'Authentic Chinese cuisine for lunch and dinner.',
  'Chinese', 'food',
  '121 1/2 Constant Spring Road, Kingston 8', 18.0250, -76.7970,
  'approved', true, true, true,
  4.2, 0, 0, 0, 35,
  0, 'CASH_PAYMENT', 'America/Jamaica',
  ARRAY['Chinese','Lunch','Dinner','Drinks'],
  '{
    "sunday":    {"open":"11:00","close":"19:00","is_open":true},
    "monday":    {"open":"11:00","close":"19:00","is_open":true},
    "tuesday":   {"open":"11:00","close":"19:00","is_open":true},
    "wednesday": {"open":"11:00","close":"19:00","is_open":true},
    "thursday":  {"open":"11:00","close":"19:00","is_open":true},
    "friday":    {"open":"13:00","close":"19:00","is_open":true},
    "saturday":  {"open":"11:00","close":"19:00","is_open":true}
  }'::jsonb
);
NOTIFY pgrst, 'reload schema';
COMMIT;
