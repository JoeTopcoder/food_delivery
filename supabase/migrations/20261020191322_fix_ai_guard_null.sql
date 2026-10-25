-- Fix: ai_guard_no_price_writes blocked ALL authenticated price writes because
-- an unset app.ai_exec made `current_setting(...) <> '1'` evaluate to NULL
-- (not TRUE), skipping the allow-path and raising on every INSERT. Use
-- IS DISTINCT FROM so unset/NULL is treated as "not the AI executor" = allowed.
CREATE OR REPLACE FUNCTION public.ai_guard_no_price_writes()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
BEGIN
  IF current_setting('app.ai_exec', true) IS DISTINCT FROM '1' THEN
    RETURN NEW; -- normal human/admin/app path is unaffected
  END IF;
  IF TG_TABLE_NAME = 'menus' THEN
    IF TG_OP = 'INSERT' OR NEW.price IS DISTINCT FROM OLD.price
       OR NEW.discount IS DISTINCT FROM OLD.discount
       OR NEW.hotbite_plus_price IS DISTINCT FROM OLD.hotbite_plus_price THEN
      RAISE EXCEPTION 'AI executor may not change product/member prices (menus)';
    END IF;
  ELSIF TG_TABLE_NAME = 'restaurants' THEN
    IF TG_OP='INSERT' OR NEW.delivery_fee IS DISTINCT FROM OLD.delivery_fee
       OR NEW.service_fee IS DISTINCT FROM OLD.service_fee
       OR NEW.commission_rate IS DISTINCT FROM OLD.commission_rate
       OR NEW.price_tier IS DISTINCT FROM OLD.price_tier THEN
      RAISE EXCEPTION 'AI executor may not change partner fees (restaurants)';
    END IF;
  ELSIF TG_TABLE_NAME = 'app_config' THEN
    IF NEW.key ILIKE '%fee%' OR NEW.key ILIKE '%price%' OR NEW.key ILIKE '%surge%'
       OR NEW.key ILIKE '%commission%' THEN
      RAISE EXCEPTION 'AI executor may not change fee/price config (app_config: %)', NEW.key;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
NOTIFY pgrst, 'reload schema';
