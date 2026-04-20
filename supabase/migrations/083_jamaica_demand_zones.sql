-- ====================================================================
-- 083: Add Kingston Jamaica demand zones
-- ====================================================================
INSERT INTO public.zones (name, latitude, longitude, radius_km, active_orders, available_drivers, demand_level, surge_multiplier) VALUES
  ('Half Way Tree',        18.0095, -76.7936, 2.5, 0, 0, 'normal', 1.0),
  ('New Kingston',         18.0069, -76.7832, 2.0, 0, 0, 'normal', 1.0),
  ('Liguanea',             18.0168, -76.7660, 2.0, 0, 0, 'normal', 1.0),
  ('Cross Roads',          18.0127, -76.7859, 1.5, 0, 0, 'normal', 1.0),
  ('Constant Spring',      18.0315, -76.7900, 2.5, 0, 0, 'normal', 1.0),
  ('Barbican',             18.0230, -76.7650, 2.0, 0, 0, 'normal', 1.0),
  ('Manor Park',           18.0297, -76.7778, 2.0, 0, 0, 'normal', 1.0),
  ('Papine',               18.0195, -76.7419, 2.0, 0, 0, 'normal', 1.0),
  ('Molynes Road',         18.0180, -76.8000, 2.0, 0, 0, 'normal', 1.0),
  ('Downtown Kingston',    17.9714, -76.7936, 3.0, 0, 0, 'low',    1.0),
  ('Red Hills',            18.0350, -76.8050, 2.5, 0, 0, 'normal', 1.0),
  ('Hope Road',            18.0132, -76.7699, 2.0, 0, 0, 'normal', 1.0)
ON CONFLICT DO NOTHING;

-- Update zone demand counts from existing orders
-- (This sets order counts so the heatmap reflects current data)
UPDATE public.zones z
SET active_orders = sub.cnt,
    demand_level = CASE
      WHEN sub.cnt >= 8 THEN 'critical'
      WHEN sub.cnt >= 5 THEN 'high'
      WHEN sub.cnt >= 3 THEN 'moderate'
      WHEN sub.cnt >= 1 THEN 'normal'
      ELSE 'low'
    END,
    surge_multiplier = CASE
      WHEN sub.cnt >= 8 THEN 2.5
      WHEN sub.cnt >= 5 THEN 2.0
      WHEN sub.cnt >= 3 THEN 1.5
      ELSE 1.0
    END,
    updated_at = NOW()
FROM (
  SELECT z2.id,
         COUNT(o.id) AS cnt
  FROM public.zones z2
  LEFT JOIN public.orders o
    ON o.status IN ('pending', 'confirmed', 'preparing', 'ready')
    AND o.driver_id IS NULL
    AND o.is_pickup = FALSE
    AND (
      -- Match orders near the zone using lat/lng distance approximation
      -- ~111km per degree lat, ~100km per degree lng at this latitude
      SQRT(
        POW((o.delivery_latitude - z2.latitude) * 111, 2) +
        POW((o.delivery_longitude - z2.longitude) * 100, 2)
      ) <= z2.radius_km
    )
  WHERE z2.is_active = TRUE
  GROUP BY z2.id
) sub
WHERE z.id = sub.id;
