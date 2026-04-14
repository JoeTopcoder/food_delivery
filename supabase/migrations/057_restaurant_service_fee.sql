-- Migration 057: Add per-restaurant service fee for pickup orders
-- Admin can set a different service fee for each restaurant.
-- Falls back to global default (AppConstants.pickupServiceFee) when NULL.

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS service_fee DOUBLE PRECISION;

COMMENT ON COLUMN public.restaurants.service_fee
  IS 'Per-restaurant pickup service fee set by admin. NULL = use global default.';
