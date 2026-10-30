-- Generalize day-scheduling from a single weekday to a SET of weekdays per item,
-- so any menu item can be made available on any combination of days via the
-- restaurant/admin menu editor. Postgres DOW: Sun=0 .. Sat=6.
-- NULL / empty  = always available (not managed by the daily sync).

ALTER TABLE menus ADD COLUMN IF NOT EXISTS available_weekdays smallint[];

-- Carry over the earlier single-weekday soups into the array form.
UPDATE menus
   SET available_weekdays = ARRAY[available_weekday]::smallint[]
 WHERE available_weekday IS NOT NULL
   AND (available_weekdays IS NULL OR array_length(available_weekdays,1) IS NULL);

-- Rewrite the daily sync to use the array. Enable an item when today's Jamaica
-- weekday is in its set; disable it otherwise. Only ever touches scheduled rows.
CREATE OR REPLACE FUNCTION sync_weekday_menu_availability()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE menus
     SET is_available = (EXTRACT(DOW FROM (now() AT TIME ZONE 'America/Jamaica'))::int = ANY(available_weekdays)),
         updated_at   = now()
   WHERE available_weekdays IS NOT NULL
     AND array_length(available_weekdays,1) > 0;
$$;

REVOKE ALL ON FUNCTION sync_weekday_menu_availability() FROM anon, authenticated;

-- Drop the now-unused single-day column.
ALTER TABLE menus DROP COLUMN IF EXISTS available_weekday;

-- Apply today's state immediately.
SELECT sync_weekday_menu_availability();

NOTIFY pgrst, 'reload schema';
