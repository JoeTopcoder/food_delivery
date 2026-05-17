-- ride_pin was inserted by create-ride-request but the column was never
-- declared in the original schema migration.
ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS ride_pin TEXT;
