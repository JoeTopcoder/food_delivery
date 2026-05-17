-- Add 'offered' status so drivers can offer without auto-assignment
ALTER TABLE public.ride_driver_requests
  DROP CONSTRAINT IF EXISTS ride_driver_requests_status_check;

ALTER TABLE public.ride_driver_requests
  ADD CONSTRAINT ride_driver_requests_status_check
  CHECK (status IN ('pending', 'offered', 'accepted', 'rejected', 'expired'));

-- Also expire 'offered' requests when sweep runs
CREATE OR REPLACE FUNCTION expire_stale_ride_requests()
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  expired_count integer;
BEGIN
  WITH updated AS (
    UPDATE ride_driver_requests
    SET status = 'expired'
    WHERE status IN ('pending', 'offered')
      AND expires_at < NOW()
    RETURNING id
  )
  SELECT COUNT(*) INTO expired_count FROM updated;
  RETURN expired_count;
END;
$$;
