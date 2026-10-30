-- Bad Chef Plating "Soup of the Day": each soup is only available on its weekday.
-- Implemented DB-side so no app change is needed — the app already respects
-- menus.is_available. A daily pg_cron job flips is_available to match the
-- Jamaica (America/Jamaica, UTC-5, no DST) weekday.

-- 1. Record which weekday each scheduled item belongs to (Postgres DOW: Sun=0..Sat=6).
--    NULL = always available (every other menu item).
ALTER TABLE menus ADD COLUMN IF NOT EXISTS available_weekday smallint;

UPDATE menus SET available_weekday = CASE name
  WHEN 'Pumpkin Chicken'                     THEN 1  -- Monday
  WHEN 'Red Peas Beef'                       THEN 2  -- Tuesday
  WHEN 'Pumpkin Chicken Foot and Cow Skin'   THEN 3  -- Wednesday
  WHEN 'Red Peas Pigtail'                    THEN 4  -- Thursday
  WHEN 'Manish Water'                        THEN 5  -- Friday
  WHEN 'Red Peas Pigtail and Chicken Foot'   THEN 6  -- Saturday
END
WHERE restaurant_id='88de57c1-3257-41e2-b8cc-674097203527'
  AND category='Soup of the Day';

-- 2. Sync function: enable only the day's soups, disable the rest. Only ever
--    touches rows that opted in via available_weekday, so nothing else is affected.
CREATE OR REPLACE FUNCTION sync_weekday_menu_availability()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE menus
     SET is_available = (available_weekday = EXTRACT(DOW FROM (now() AT TIME ZONE 'America/Jamaica'))::int),
         updated_at   = now()
   WHERE available_weekday IS NOT NULL;
$$;

REVOKE ALL ON FUNCTION sync_weekday_menu_availability() FROM anon, authenticated;

-- 3. Schedule it daily at 00:05 Jamaica time (= 05:05 UTC).
SELECT cron.unschedule('sync_weekday_menu_availability')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname='sync_weekday_menu_availability');
SELECT cron.schedule('sync_weekday_menu_availability', '5 5 * * *',
                     $$SELECT sync_weekday_menu_availability();$$);

-- 4. Set today's state immediately.
SELECT sync_weekday_menu_availability();

NOTIFY pgrst, 'reload schema';
