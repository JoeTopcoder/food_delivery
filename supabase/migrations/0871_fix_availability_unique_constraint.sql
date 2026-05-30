-- Fix: add UNIQUE(provider_id, day_of_week) to car_service_provider_availability
-- Without this constraint, upsert(onConflict: 'provider_id,day_of_week') inserts
-- new rows instead of updating existing ones, creating duplicates.

-- 1. Remove duplicates — keep the row with the most recent id (gen_random_uuid is
--    roughly monotonic in Postgres 13+) for each (provider_id, day_of_week) pair.
DELETE FROM public.car_service_provider_availability
WHERE id NOT IN (
  SELECT DISTINCT ON (provider_id, day_of_week) id
  FROM   public.car_service_provider_availability
  ORDER  BY provider_id, day_of_week, id DESC
);

-- 2. Add the unique constraint so future upserts work correctly.
ALTER TABLE public.car_service_provider_availability
  ADD CONSTRAINT uq_provider_day UNIQUE (provider_id, day_of_week);
