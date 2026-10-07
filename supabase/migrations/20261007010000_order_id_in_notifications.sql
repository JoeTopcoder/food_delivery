-- Standardize the ORDER ID shown in notifications on the human receipt number
-- (FD-YYYYMMDD-NNNN) instead of a short UUID, so every message/area shows the
-- same ID. Rewrites the order notification functions in place, replacing
-- upper(substring(id,1,8)) with COALESCE(receipt_number, left(id,8)).
-- (Ride / car-service notifications are left as-is: those have no receipt_number.)
DO $$
DECLARE r record; d text; up text;
        pat_up text := 'upper\(\s*substring\(\s*NEW\.id::text\s*,\s*1\s*,\s*8\s*\)\s*\)';
        pat_bare text := 'substring\(\s*NEW\.id::text\s*,\s*1\s*,\s*8\s*\)';
BEGIN
  FOR r IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND p.proname IN ('notify_admin_new_order','notify_customer_on_order_placed',
                        'notify_customer_on_order_status_change','notify_restaurant_new_order')
  LOOP
    d := pg_get_functiondef(r.oid);
    d := regexp_replace(d, pat_up,  'COALESCE(NEW.receipt_number, upper(left(NEW.id::text,8)))', 'gi');
    d := regexp_replace(d, pat_bare,'COALESCE(NEW.receipt_number, left(NEW.id::text,8))', 'gi');
    EXECUTE d;
  END LOOP;
END $$;
NOTIFY pgrst, 'reload schema';
