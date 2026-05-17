-- Auto-approve all existing drivers for ride sharing.
-- is_ride_driver_approved defaulted to FALSE, blocking all driver dispatch.
-- Since there's no admin approval UI, approval is granted when a driver
-- enables ride sharing mode (handled in the app's updateDriverAvailability call).
UPDATE public.drivers
SET is_ride_driver_approved = TRUE
WHERE is_ride_driver_approved = FALSE OR is_ride_driver_approved IS NULL;

-- Also add 'scheduled' to the ride_status check constraint (was missing, breaks scheduled rides).
ALTER TABLE public.ride_requests
  DROP CONSTRAINT IF EXISTS ride_requests_ride_status_check;

ALTER TABLE public.ride_requests
  ADD CONSTRAINT ride_requests_ride_status_check
  CHECK (ride_status IN (
    'requested', 'searching_driver', 'scheduled',
    'driver_assigned', 'driver_arriving', 'driver_arrived',
    'ride_started', 'ride_completed', 'cancelled', 'failed'
  ));
