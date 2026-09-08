-- Migration: rebrand the notification text that lives in the database.
--
-- The Dart and edge-function rename covered source. Three live functions
-- generate customer-facing copy from inside Postgres, so the old brand would
-- have kept going out in push notifications and wallet history no matter what
-- the app said.
--
-- Each is rewritten from its OWN current definition rather than from a
-- migration file: definitions in this repo drift from what is actually
-- deployed, and re-applying an older body to fix a string would silently
-- revert whatever else had changed. pg_get_functiondef is the source of truth.

DO $rebrand$
DECLARE
  r        RECORD;
  v_def    TEXT;
  v_new    TEXT;
  v_count  INT := 0;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (p.prosrc LIKE '%MealHub%' OR p.prosrc LIKE '%7Dash%')
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := replace(replace(v_def, 'MealHub', 'Quickdash'), '7Dash', 'Quickdash');

    IF v_new <> v_def THEN
      EXECUTE v_new;
      v_count := v_count + 1;
      RAISE NOTICE 'rebranded %', r.proname;
    END IF;
  END LOOP;

  RAISE NOTICE 'functions rebranded: %', v_count;
END
$rebrand$;

NOTIFY pgrst, 'reload schema';
