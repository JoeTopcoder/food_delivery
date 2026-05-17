-- ============================================================
-- JMD Pricing update + ride booking fixes
-- ============================================================

-- Add per_mile_rate column so the edge function can read it directly
ALTER TABLE public.ride_pricing_settings
  ADD COLUMN IF NOT EXISTS per_mile_rate NUMERIC NOT NULL DEFAULT 250;

-- Update pricing to J$250/mile (minimum J$500, 20% platform fee)
UPDATE public.ride_pricing_settings
SET
  base_fare                    = 0,
  per_km_rate                  = 155.35,   -- J$250/mile ÷ 1.60934 km/mile
  per_minute_rate              = 0,
  minimum_fare                 = 500,
  per_mile_rate                = 250,
  platform_commission_percent  = 20,
  surge_multiplier             = 1.0,
  updated_at                   = NOW()
WHERE active = TRUE;

-- ============================================================
-- Ensure 'paid' is a valid payment_status for ride_requests
-- (card payments are pre-collected via Stripe Payment Sheet)
-- ============================================================
ALTER TABLE public.ride_requests
  DROP CONSTRAINT IF EXISTS ride_requests_payment_status_check;

ALTER TABLE public.ride_requests
  ADD CONSTRAINT ride_requests_payment_status_check
  CHECK (payment_status IN (
    'pending','authorized','paid','cash_pending',
    'cash_collected','failed','refunded','cancelled'
  ));
