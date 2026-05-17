-- =============================================================================
-- FIX 1: Add 'offered' to ride_driver_requests.status CHECK constraint.
-- The respond-to-ride-request edge function sets status='offered' when a driver
-- accepts a request, but 'offered' was missing from the constraint — causing a
-- DB error (500) every time a driver tried to accept, silently blocking the flow.
-- =============================================================================
ALTER TABLE public.ride_driver_requests
  DROP CONSTRAINT IF EXISTS ride_driver_requests_status_check;

ALTER TABLE public.ride_driver_requests
  ADD CONSTRAINT ride_driver_requests_status_check
  CHECK (status IN ('pending', 'offered', 'accepted', 'rejected', 'expired'));

-- =============================================================================
-- FIX 2: Create the DB trigger that assigns the driver when the customer
-- selects them (status → 'accepted'). The select-driver edge function comments
-- say "fires the DB trigger which assigns the driver" but the trigger was never
-- created, so ride_requests.driver_id stayed NULL and ride_status never changed
-- to 'driver_assigned'.
-- =============================================================================
CREATE OR REPLACE FUNCTION public.assign_driver_on_request_accept()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only fire on the transition pending/offered → accepted
  IF NEW.status = 'accepted' AND OLD.status IN ('pending', 'offered') THEN
    UPDATE public.ride_requests
    SET
      driver_id   = NEW.driver_id,
      ride_status = 'driver_assigned',
      accepted_at = NOW(),
      updated_at  = NOW()
    WHERE id = NEW.ride_id
      AND ride_status = 'searching_driver';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_assign_driver_on_accept ON public.ride_driver_requests;

CREATE TRIGGER trg_assign_driver_on_accept
  AFTER UPDATE ON public.ride_driver_requests
  FOR EACH ROW
  EXECUTE FUNCTION public.assign_driver_on_request_accept();
