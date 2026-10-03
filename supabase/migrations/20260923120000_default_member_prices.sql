-- Ensure every restaurant menu item has a HotBite+ member price below its
-- regular (discounted) price, so active members always see member pricing.
-- Configurable default saving; owner-set member prices are never overwritten.

INSERT INTO public.app_config (key, value)
VALUES ('membership_default_discount_pct', '10')
ON CONFLICT (key) DO NOTHING;

-- Backfill: any food menu item without a member price gets one at
-- (discounted price) * (1 - default%). Rounded to whole currency.
UPDATE public.menus m
SET hotbite_plus_price = round(
      (m.price * (1 - COALESCE(m.discount,0)/100.0)) *
      (1 - (SELECT value::numeric FROM public.app_config WHERE key='membership_default_discount_pct')/100.0)
    )
WHERE m.hotbite_plus_price IS NULL
  AND COALESCE(m.price,0) > 0
  AND COALESCE(m.product_type,'food') <> 'grocery';

-- Keep it true for new/edited items: default a missing member price on write.
CREATE OR REPLACE FUNCTION public.default_member_price()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE pct numeric;
BEGIN
  IF NEW.hotbite_plus_price IS NULL
     AND COALESCE(NEW.price,0) > 0
     AND COALESCE(NEW.product_type,'food') <> 'grocery' THEN
    SELECT value::numeric INTO pct FROM public.app_config
      WHERE key='membership_default_discount_pct';
    pct := COALESCE(pct, 10);
    NEW.hotbite_plus_price :=
      round((NEW.price * (1 - COALESCE(NEW.discount,0)/100.0)) * (1 - pct/100.0));
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_default_member_price ON public.menus;
CREATE TRIGGER trg_default_member_price
  BEFORE INSERT OR UPDATE ON public.menus
  FOR EACH ROW EXECUTE FUNCTION public.default_member_price();

NOTIFY pgrst, 'reload schema';
