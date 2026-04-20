-- ============================================================================
-- Migration 087: Backfill distance_km on orders from restaurant/delivery coords
-- ============================================================================

-- Update all orders that have delivery coords but no distance_km
UPDATE orders o
SET distance_km = ROUND(
  (6371 * 2 * ASIN(SQRT(
    POWER(SIN(RADIANS(o.delivery_latitude - r.latitude) / 2), 2) +
    COS(RADIANS(r.latitude)) * COS(RADIANS(o.delivery_latitude)) *
    POWER(SIN(RADIANS(o.delivery_longitude - r.longitude) / 2), 2)
  )))::numeric, 2
)
FROM restaurants r
WHERE r.id = o.restaurant_id
  AND o.distance_km IS NULL
  AND o.delivery_latitude IS NOT NULL
  AND o.delivery_longitude IS NOT NULL
  AND r.latitude IS NOT NULL
  AND r.longitude IS NOT NULL;

-- Now re-run the driver_stats backfill with updated distance data
UPDATE driver_stats ds SET
  total_distance_km = COALESCE(agg.total_dist, 0),
  updated_at = NOW()
FROM (
  SELECT o.driver_id,
         ROUND(COALESCE(SUM(o.distance_km) FILTER (WHERE o.status = 'delivered'), 0)::numeric, 2) AS total_dist
  FROM orders o
  WHERE o.driver_id IS NOT NULL
    AND o.ordered_at >= NOW() - INTERVAL '30 days'
  GROUP BY o.driver_id
) agg
WHERE agg.driver_id = ds.driver_id;

-- Also update avg_customer_rating from orders with driver_rating
-- For drivers that have actual ratings
UPDATE driver_stats ds SET
  avg_customer_rating = COALESCE(agg.avg_rating, ds.avg_customer_rating),
  updated_at = NOW()
FROM (
  SELECT o.driver_id,
         ROUND(AVG(o.driver_rating)::numeric, 2) AS avg_rating
  FROM orders o
  WHERE o.driver_id IS NOT NULL
    AND o.driver_rating IS NOT NULL
    AND o.ordered_at >= NOW() - INTERVAL '30 days'
  GROUP BY o.driver_id
) agg
WHERE agg.driver_id = ds.driver_id;

-- Sync driver_stats avg rating back to drivers table for those with real ratings
UPDATE drivers d SET
  rating = ds.avg_customer_rating,
  updated_at = NOW()
FROM driver_stats ds
WHERE ds.driver_id = d.id
  AND ds.avg_customer_rating > 0
  AND ds.orders_accepted > 0;

-- Recalculate scores with updated data
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN SELECT driver_id FROM driver_stats WHERE orders_accepted > 0 LOOP
    PERFORM calculate_driver_score(rec.driver_id);
  END LOOP;
END;
$$;

-- Update bonus multipliers
UPDATE driver_stats SET
  bonus_multiplier = CASE tier
    WHEN 'elite' THEN 1.20
    WHEN 'gold'  THEN 1.10
    WHEN 'silver' THEN 1.05
    ELSE 1.0
  END,
  priority_dispatch = (tier IN ('gold', 'elite'))
WHERE orders_accepted > 0;
