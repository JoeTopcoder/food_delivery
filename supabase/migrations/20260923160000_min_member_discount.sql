-- Enforce a minimum HotBite+ member discount. A merchant-set member price must
-- be at least `minimum_member_discount_percentage` below the regular price
-- (default 5%). Configurable by admin; the auto-default (10%) already satisfies it.
INSERT INTO public.app_config (key, value)
VALUES ('minimum_member_discount_percentage', '5')
ON CONFLICT (key) DO NOTHING;

-- Extend the existing default/guard trigger function: reject an owner-set member
-- price that doesn't meet the minimum discount (server-authoritative).
CREATE OR REPLACE FUNCTION public.default_member_price()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE pct numeric; minpct numeric; regular numeric;
BEGIN
  IF COALESCE(NEW.product_type,'food') = 'grocery' THEN
    RETURN NEW; -- grocery handled separately
  END IF;

  regular := NEW.price * (1 - COALESCE(NEW.discount,0)/100.0);

  SELECT value::numeric INTO minpct FROM public.app_config
    WHERE key='minimum_member_discount_percentage';
  minpct := COALESCE(minpct, 5);

  IF NEW.hotbite_plus_price IS NULL AND COALESCE(NEW.price,0) > 0 THEN
    -- No member price set → default one at the configured saving.
    SELECT value::numeric INTO pct FROM public.app_config
      WHERE key='membership_default_discount_pct';
    pct := GREATEST(COALESCE(pct, 10), minpct);
    NEW.hotbite_plus_price := round(regular * (1 - pct/100.0));
  ELSIF NEW.hotbite_plus_price IS NOT NULL AND COALESCE(NEW.price,0) > 0 THEN
    -- Owner-set member price must be at least minpct below the regular price.
    IF NEW.hotbite_plus_price > regular * (1 - minpct/100.0) + 0.01 THEN
      RAISE EXCEPTION 'HotBite+ member price must be at least %%% below the regular price', minpct
        USING ERRCODE = 'check_violation';
    END IF;
  END IF;
  RETURN NEW;
END;
$fn$;

NOTIFY pgrst, 'reload schema';
