-- Verify ride_pricing_settings table exists and has data
SELECT 
  table_name 
FROM information_schema.tables 
WHERE table_schema = 'public' 
  AND table_name = 'ride_pricing_settings';

-- Show all pricing settings
SELECT * FROM public.ride_pricing_settings;

-- Show active pricing settings only
SELECT * FROM public.ride_pricing_settings WHERE active = true;

-- Count total records
SELECT COUNT(*) as total_records FROM public.ride_pricing_settings;
