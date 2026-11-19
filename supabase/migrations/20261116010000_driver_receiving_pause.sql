-- Admin on/off switch for a driver receiving orders. An admin can pause a
-- driver (rider) from being offered new orders for a set period — an hour, two
-- hours, the rest of the day — or indefinitely, and flip them back on.
--
--   receiving_paused_until IS NULL            -> ON  (receives orders normally)
--   receiving_paused_until > now()            -> OFF (paused until that time)
--   receiving_paused_until = 'infinity'       -> OFF indefinitely (until turned on)
--
-- A paused driver keeps their account and approval; they simply aren't offered
-- new orders while paused. The pause auto-expires on its own at the set time.
BEGIN;

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS receiving_paused_until timestamptz;

COMMENT ON COLUMN public.drivers.receiving_paused_until IS
  'Admin pause: NULL = receiving orders; a future timestamp (or infinity) = paused until then.';

COMMIT;

NOTIFY pgrst, 'reload schema';
