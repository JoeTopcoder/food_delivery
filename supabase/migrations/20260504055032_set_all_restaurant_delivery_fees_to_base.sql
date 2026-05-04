-- ====================================================================
-- Set every restaurant's delivery_fee to the base fee defined in app_config.
-- Falls back to 50.0 (the seeded default) if the config row is missing
-- or the value is not a valid number.
-- ====================================================================

DO $$
DECLARE
  base_fee DOUBLE PRECISION;
BEGIN
  SELECT NULLIF(value, '')::DOUBLE PRECISION
    INTO base_fee
  FROM public.app_config
  WHERE key = 'delivery_base_fee'
  LIMIT 1;

  IF base_fee IS NULL THEN
    base_fee := 50.0;
  END IF;

  UPDATE public.restaurants
  SET delivery_fee = base_fee,
      updated_at   = NOW()
  WHERE delivery_fee IS DISTINCT FROM base_fee;

  RAISE NOTICE 'Aligned restaurants.delivery_fee to base fee = %', base_fee;
END $$;
