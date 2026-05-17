-- Add cancellation fee and waiting fee tracking to ride_requests
ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS cancellation_fee  DECIMAL(10,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS waiting_started_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS waiting_fee_per_min DECIMAL(10,2) DEFAULT 75.0;
