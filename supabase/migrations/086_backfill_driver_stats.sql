-- ============================================================================
-- Migration 086: Backfill driver_stats for all drivers with deliveries
-- Calculates actual performance metrics from order history + recalculates tier
-- ============================================================================

-- Step 1: Insert a driver_stats row for every driver, computed from their orders
INSERT INTO driver_stats (
  driver_id,
  acceptance_rate,
  completion_rate,
  on_time_rate,
  avg_delivery_minutes,
  avg_customer_rating,
  avg_tip_percent,
  total_tips,
  total_distance_km,
  orders_accepted,
  orders_declined,
  updated_at
)
SELECT
  d.id AS driver_id,
  -- acceptance_rate: ratio of orders assigned vs declined (approximate)
  CASE
    WHEN (COALESCE(agg.total_orders, 0) + COALESCE(dec.declined_count, 0)) > 0
    THEN ROUND((COALESCE(agg.total_orders, 0)::numeric /
         (COALESCE(agg.total_orders, 0) + COALESCE(dec.declined_count, 0))) * 100, 1)
    ELSE 100
  END AS acceptance_rate,
  -- completion_rate: delivered / total assigned
  CASE
    WHEN COALESCE(agg.total_orders, 0) > 0
    THEN ROUND((COALESCE(agg.completed_orders, 0)::numeric / agg.total_orders) * 100, 1)
    ELSE 0
  END AS completion_rate,
  -- on_time_rate: delivered within 45 min of ordered_at
  CASE
    WHEN COALESCE(agg.completed_orders, 0) > 0
    THEN ROUND((COALESCE(agg.on_time_count, 0)::numeric / agg.completed_orders) * 100, 1)
    ELSE 0
  END AS on_time_rate,
  -- avg_delivery_minutes
  COALESCE(ROUND(agg.avg_delivery_min::numeric, 1), 0) AS avg_delivery_minutes,
  -- avg_customer_rating
  COALESCE(ROUND(agg.avg_rating::numeric, 2), COALESCE(d.rating, 0)) AS avg_customer_rating,
  -- avg_tip_percent
  COALESCE(ROUND(agg.avg_tip_pct::numeric, 1), 0) AS avg_tip_percent,
  -- total_tips
  COALESCE(ROUND(agg.total_tips::numeric, 2), 0) AS total_tips,
  -- total_distance_km
  COALESCE(ROUND(agg.total_dist_km::numeric, 2), 0) AS total_distance_km,
  -- orders_accepted (30-day window)
  COALESCE(agg.total_orders, 0) AS orders_accepted,
  -- orders_declined
  COALESCE(dec.declined_count, 0) AS orders_declined,
  NOW()
FROM drivers d
LEFT JOIN LATERAL (
  SELECT
    COUNT(*)::int AS total_orders,
    COUNT(*) FILTER (WHERE o.status = 'delivered')::int AS completed_orders,
    COUNT(*) FILTER (WHERE o.status = 'delivered'
      AND o.completed_at IS NOT NULL
      AND o.ordered_at IS NOT NULL
      AND EXTRACT(EPOCH FROM (o.completed_at - o.ordered_at)) / 60 <= 45
    )::int AS on_time_count,
    AVG(
      CASE WHEN o.status = 'delivered' AND o.completed_at IS NOT NULL AND o.ordered_at IS NOT NULL
           THEN EXTRACT(EPOCH FROM (o.completed_at - o.ordered_at)) / 60
      END
    ) AS avg_delivery_min,
    AVG(o.driver_rating) FILTER (WHERE o.driver_rating IS NOT NULL) AS avg_rating,
    AVG(
      CASE WHEN o.driver_tip IS NOT NULL AND o.delivery_fee IS NOT NULL AND o.delivery_fee > 0
           THEN (o.driver_tip / o.delivery_fee) * 100
      END
    ) AS avg_tip_pct,
    COALESCE(SUM(o.driver_tip) FILTER (WHERE o.status = 'delivered'), 0) AS total_tips,
    COALESCE(SUM(o.distance_km) FILTER (WHERE o.status = 'delivered'), 0) AS total_dist_km
  FROM orders o
  WHERE o.driver_id = d.id
    AND o.ordered_at >= NOW() - INTERVAL '30 days'
) agg ON true
LEFT JOIN LATERAL (
  SELECT COUNT(*)::int AS declined_count
  FROM driver_declined_orders ddo
  WHERE ddo.driver_id = d.id
    AND ddo.declined_at >= NOW() - INTERVAL '30 days'
) dec ON true
ON CONFLICT (driver_id) DO UPDATE SET
  acceptance_rate = EXCLUDED.acceptance_rate,
  completion_rate = EXCLUDED.completion_rate,
  on_time_rate = EXCLUDED.on_time_rate,
  avg_delivery_minutes = EXCLUDED.avg_delivery_minutes,
  avg_customer_rating = EXCLUDED.avg_customer_rating,
  avg_tip_percent = EXCLUDED.avg_tip_percent,
  total_tips = EXCLUDED.total_tips,
  total_distance_km = EXCLUDED.total_distance_km,
  orders_accepted = EXCLUDED.orders_accepted,
  orders_declined = EXCLUDED.orders_declined,
  updated_at = NOW();

-- Step 2: Recalculate score & tier for every driver
DO $$
DECLARE
  rec RECORD;
BEGIN
  FOR rec IN SELECT driver_id FROM driver_stats LOOP
    PERFORM calculate_driver_score(rec.driver_id);
  END LOOP;
END;
$$;

-- Step 3: Set bonus multipliers based on new tiers
UPDATE driver_stats SET
  bonus_multiplier = CASE tier
    WHEN 'elite' THEN 1.20
    WHEN 'gold'  THEN 1.10
    WHEN 'silver' THEN 1.05
    ELSE 1.0
  END,
  priority_dispatch = (tier IN ('gold', 'elite'));
