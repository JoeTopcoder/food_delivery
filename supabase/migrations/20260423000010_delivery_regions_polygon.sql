-- Add polygon column to delivery_regions.
-- Stores an ordered array of {lat, lng} objects, e.g.:
--   [{"lat": 18.12, "lng": -77.30}, ...]
-- NULL means the region still uses the legacy circle (radius_km) approach.
ALTER TABLE public.delivery_regions
  ADD COLUMN IF NOT EXISTS polygon JSONB DEFAULT NULL;
