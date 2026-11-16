-- A restaurant with no reviews should not show a rating score. Several
-- (7krave-imported) restaurants carry a seeded rating (e.g. 4.2) with
-- review_count = 0. Null those out so the app shows "New" instead of a fake
-- score. Restaurants with real reviews keep their computed rating.
BEGIN;

UPDATE public.restaurants
   SET rating = NULL
 WHERE rating IS NOT NULL
   AND COALESCE(review_count, 0) = 0;

COMMIT;

NOTIFY pgrst, 'reload schema';
