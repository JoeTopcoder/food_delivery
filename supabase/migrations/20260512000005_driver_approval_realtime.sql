-- Auto-approve all existing drivers for ride sharing (change default too)
UPDATE public.drivers SET is_ride_driver_approved = TRUE;
ALTER TABLE public.drivers ALTER COLUMN is_ride_driver_approved SET DEFAULT TRUE;

-- Enable Supabase Realtime for the ride tables so the Flutter .stream() API
-- receives live inserts/updates (critical for driver request popups).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_driver_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_driver_requests;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'ride_requests'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ride_requests;
  END IF;
END $$;
