-- ====================================================================
-- 084: USD-ONLY PRICING + $1.50/MILE DRIVER PAY COMPLIANCE
-- Converts Jamaica seed data from JMD to USD, updates driver pay rates
-- ====================================================================

-- ── 1. Fix Jamaica menu prices (JMD → USD, ~155 JMD = 1 USD) ──────
UPDATE public.menus SET
  price = ROUND((price / 155.0)::numeric, 2)
WHERE restaurant_id IN (
  SELECT id FROM public.restaurants
  WHERE address ILIKE '%Kingston%' OR address ILIKE '%Jamaica%'
) AND price > 50;

-- ── 2. Fix Jamaica order amounts (JMD → USD) ──────────────────────
UPDATE public.orders SET
  subtotal = ROUND((subtotal / 155.0)::numeric, 2),
  total_amount = ROUND((total_amount / 155.0)::numeric, 2),
  delivery_fee = CASE
    WHEN delivery_fee > 20 THEN ROUND((delivery_fee / 155.0)::numeric, 2)
    ELSE delivery_fee
  END,
  driver_tip = CASE
    WHEN driver_tip IS NOT NULL AND driver_tip > 20 THEN ROUND((driver_tip / 155.0)::numeric, 2)
    ELSE driver_tip
  END
WHERE delivery_address ILIKE '%Kingston%'
   OR delivery_address ILIKE '%Jamaica%'
   OR restaurant_id IN (
     SELECT id FROM public.restaurants
     WHERE address ILIKE '%Kingston%' OR address ILIKE '%Jamaica%'
   );

-- ── 3. Update driver pay rate to $1.50/mile = $0.93/km ────────────
UPDATE public.app_config SET value = '0.93', updated_at = NOW()
WHERE key = 'driver_rate_per_km';

-- ── 4. Add driver_rate_per_mile config key ─────────────────────────
INSERT INTO public.app_config (key, value, value_type, description) VALUES
  ('driver_rate_per_mile', '1.50', 'number', 'Driver pay per mile driven ($1.50/mi compliance)')
ON CONFLICT (key) DO UPDATE SET value = '1.50', updated_at = NOW();

-- ── 5. Fix default_delivery_fee if set to JMD value ───────────────
UPDATE public.app_config SET value = '5.0', updated_at = NOW()
WHERE key = 'default_delivery_fee' AND value::numeric > 20;

-- ── 6. Ensure Cayman seed data delivery fees are USD-reasonable ────
-- (Cayman data was already in reasonable ranges, skip if OK)
