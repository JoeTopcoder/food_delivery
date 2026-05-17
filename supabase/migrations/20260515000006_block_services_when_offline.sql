-- Trigger: prevent a driver from ENABLING services while their account is offline.
-- Removing services (shrinking active_services) is always allowed.

CREATE OR REPLACE FUNCTION fn_block_enable_services_when_offline()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Only applies when active_services is being updated
  -- Block if driver is offline AND services are being ADDED (new array is longer)
  IF NEW.is_available = FALSE
     AND array_length(NEW.active_services, 1) > COALESCE(array_length(OLD.active_services, 1), 0)
  THEN
    RAISE EXCEPTION 'Driver account is offline. Go online before enabling services.'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_block_enable_services_when_offline ON drivers;

CREATE TRIGGER trg_block_enable_services_when_offline
  BEFORE UPDATE OF active_services ON drivers
  FOR EACH ROW
  EXECUTE FUNCTION fn_block_enable_services_when_offline();
