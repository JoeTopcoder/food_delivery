-- Standardize the order ID shown EVERYWHERE on the short order id
-- (first 8 of the UUID, upper-cased) — which the app UI already uses in all
-- order/cancellation/driver screens. Reverts the receipt_number swap in the
-- notification functions so notifications match the in-app displays exactly.
DO $$
DECLARE r record; d text;
BEGIN
  FOR r IN
    SELECT p.oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.prokind='f'
      AND p.proname IN ('notify_admin_new_order','notify_customer_on_order_placed',
                        'notify_customer_on_order_status_change','notify_restaurant_new_order')
  LOOP
    d := pg_get_functiondef(r.oid);
    d := regexp_replace(d, 'COALESCE\(NEW\.receipt_number,\s*(upper\(left\(NEW\.id::text,\s*8\)\))\)', '\1', 'gi');
    d := regexp_replace(d, 'COALESCE\(NEW\.receipt_number,\s*(left\(NEW\.id::text,\s*8\))\)', '\1', 'gi');
    EXECUTE d;
  END LOOP;
END $$;
NOTIFY pgrst, 'reload schema';
