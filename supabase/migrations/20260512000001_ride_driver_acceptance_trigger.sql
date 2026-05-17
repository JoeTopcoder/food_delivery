-- Migration: Ride driver acceptance trigger
-- Created: 2026-05-12
--
-- This migration adds:
--   1. A trigger that atomically assigns a driver to a ride when a
--      ride_driver_requests row transitions to 'accepted'.
--   2. A function + (optional) cron job to expire stale pending requests.
--   3. Realtime publication for ride_driver_requests and ride_requests.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. handle_driver_request_acceptance()
--    Fires AFTER UPDATE on ride_driver_requests.
--    When a row moves into the 'accepted' state this function:
--      a. Claims the ride by setting driver_id / ride_status / accepted_at,
--         but ONLY if the ride is still in 'searching_driver' (safe re-entry).
--      b. Expires every other pending request for the same ride.
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION handle_driver_request_acceptance()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only act when a row transitions INTO the 'accepted' state.
  IF NEW.status = 'accepted' AND OLD.status IS DISTINCT FROM 'accepted' THEN

    -- a. Assign the driver to the ride (conditional to avoid overwriting
    --    a ride that another concurrent accept already claimed).
    UPDATE ride_requests
    SET
      driver_id   = NEW.driver_id,
      ride_status = 'driver_assigned',
      accepted_at = NOW()
    WHERE id          = NEW.ride_id
      AND ride_status = 'searching_driver';

    -- b. Expire every other pending request for this ride so drivers
    --    are not left waiting for a ride that has already been filled.
    UPDATE ride_driver_requests
    SET status = 'expired'
    WHERE ride_id = NEW.ride_id
      AND id      != NEW.id
      AND status  = 'pending';

  END IF;

  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Trigger
-- ─────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS on_driver_request_accepted ON ride_driver_requests;

CREATE TRIGGER on_driver_request_accepted
AFTER UPDATE ON ride_driver_requests
FOR EACH ROW
EXECUTE FUNCTION handle_driver_request_acceptance();

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. expire_stale_ride_requests()
--    Marks all pending requests whose expiry time has passed as 'expired'.
--    Returns the number of rows updated so callers can log the count.
-- ─────────────────────────────────────────────────────────────────────────────
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
    WHERE status     = 'pending'
      AND expires_at < NOW()
    RETURNING id
  )
  SELECT COUNT(*) INTO expired_count FROM updated;

  RETURN expired_count;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. Optional cron job (requires pg_cron extension).
--    Runs every minute to sweep up expired pending requests.
--    Wrapped in a DO block so the migration does not fail when pg_cron is not
--    enabled (e.g. local development databases).
-- ─────────────────────────────────────────────────────────────────────────────
DO $$
BEGIN
  PERFORM cron.schedule(
    'expire-ride-requests',   -- job name (unique)
    '* * * * *',              -- every minute
    'SELECT expire_stale_ride_requests()'
  );
  RAISE NOTICE 'pg_cron job "expire-ride-requests" scheduled successfully.';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'pg_cron not available — skipping cron job setup. '
                 'Run expire_stale_ride_requests() manually or via your own scheduler.';
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. Realtime publication
--    Drivers listen on ride_driver_requests for incoming ride pings.
--    Customers (and drivers) listen on ride_requests for status changes.
-- ─────────────────────────────────────────────────────────────────────────────

-- ride_driver_requests — new table, safe to add unconditionally.
ALTER PUBLICATION supabase_realtime ADD TABLE ride_driver_requests;

-- ride_requests — may already be in the publication; use a DO block to
-- suppress the "relation already exists in publication" error.
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE ride_requests;
  RAISE NOTICE 'ride_requests added to supabase_realtime publication.';
EXCEPTION
  WHEN duplicate_object THEN
    RAISE NOTICE 'ride_requests is already in supabase_realtime — no change needed.';
END;
$$;
