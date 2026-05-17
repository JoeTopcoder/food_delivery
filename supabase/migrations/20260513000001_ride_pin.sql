-- Add ride_pin column to ride_requests for OTP verification before starting a ride
ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS ride_pin VARCHAR(6);
