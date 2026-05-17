-- Add active_services column to drivers table
-- Stores which service types the driver has enabled: food_delivery, package_delivery, ride_sharing
ALTER TABLE drivers
  ADD COLUMN IF NOT EXISTS active_services TEXT[] DEFAULT ARRAY['food_delivery']::TEXT[];
