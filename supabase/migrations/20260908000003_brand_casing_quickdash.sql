-- Migration: the brand is "QuickDash", capital D.
--
-- The previous rebrand wrote "Quickdash" into the three functions that
-- generate customer-facing copy. The logo lockup capitalises the D, so the
-- push notifications and wallet history should too.
--
-- Rewritten from each function's own current definition, for the same reason
-- as before: the deployed body is the only trustworthy source.

DO $casing$
DECLARE
  r     RECORD;
  v_def TEXT;
  v_new TEXT;
BEGIN
  FOR r IN
    SELECT p.oid, p.proname
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.prosrc LIKE '%Quickdash%'
  LOOP
    v_def := pg_get_functiondef(r.oid);
    v_new := replace(v_def, 'Quickdash', 'QuickDash');
    IF v_new <> v_def THEN
      EXECUTE v_new;
      RAISE NOTICE 'recased %', r.proname;
    END IF;
  END LOOP;
END
$casing$;

NOTIFY pgrst, 'reload schema';
