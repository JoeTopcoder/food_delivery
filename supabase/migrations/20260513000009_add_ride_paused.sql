-- Add ride_paused status and pause_reason column

ALTER TABLE public.ride_requests DROP CONSTRAINT IF EXISTS ride_requests_ride_status_check;
ALTER TABLE public.ride_requests ADD CONSTRAINT ride_requests_ride_status_check
  CHECK (ride_status IN (
    'requested','searching_driver','scheduled','driver_assigned',
    'driver_arriving','driver_arrived','ride_started','ride_paused',
    'ride_completed','cancelled','failed'
  ));

ALTER TABLE public.ride_requests ADD COLUMN IF NOT EXISTS pause_reason TEXT;
