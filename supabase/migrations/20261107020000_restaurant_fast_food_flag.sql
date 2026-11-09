-- Classify restaurants as fast food so the admin order screen can split orders
-- into Fast Food vs Regular. cuisine_type alone is inconsistent (Bubble Chick =
-- "Fast Food", KFC = "Fried Chicken", Church's = "Jamaican"), so this is an
-- explicit flag, seeded from cuisine type + known quick-service chain names and
-- adjustable afterwards.
BEGIN;

ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS is_fast_food boolean NOT NULL DEFAULT false;

UPDATE restaurants
SET is_fast_food = true
WHERE store_type IN ('food', 'both')
  AND (
    cuisine_type IN ('Fast Food', 'Fried Chicken')
    OR name ILIKE '%kfc%'
    OR name ILIKE '%church%'
    OR name ILIKE '%bubble chick%'
    OR name ILIKE '%pizza hut%'
    OR name ILIKE '%burger king%'
    OR name ILIKE '%popeye%'
    OR name ILIKE '%wendy%'
    OR name ILIKE '%mcdonald%'
  );

COMMIT;

NOTIFY pgrst, 'reload schema';
