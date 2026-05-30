-- get_cart_recommendations
-- Analyses a user's co-ordering and order history to suggest nearby restaurants
-- they frequently pair with what is already in their cart.
-- Returns ranked recommendations with reason strings.

CREATE OR REPLACE FUNCTION public.get_cart_recommendations(
  p_user_id            UUID,
  p_cart_restaurant_ids UUID[],
  p_delivery_lat        DOUBLE PRECISION DEFAULT NULL,
  p_delivery_lng        DOUBLE PRECISION DEFAULT NULL,
  p_max_distance_km     DOUBLE PRECISION DEFAULT 15.0,
  p_limit               INT              DEFAULT 3
)
RETURNS TABLE (
  restaurant_id           UUID,
  restaurant_name         TEXT,
  cuisine_type            TEXT,
  rating                  NUMERIC,
  image_url               TEXT,
  estimated_delivery_time INT,
  distance_km             DOUBLE PRECISION,
  delivery_fee            NUMERIC,
  behavior_score          DOUBLE PRECISION,
  final_score             DOUBLE PRECISION,
  reason                  TEXT,
  is_co_order             BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_cart_names TEXT;
BEGIN

  -- Build a comma-separated list of current cart restaurant names (for reason strings)
  SELECT string_agg(name, ' & ' ORDER BY name)
  INTO   v_cart_names
  FROM   restaurants
  WHERE  id = ANY(p_cart_restaurant_ids);

  RETURN QUERY
  WITH

  -- ── 1. Co-order signal: restaurants ordered together with cart restaurants ──
  co_order_scores AS (
    SELECT
      ro2.restaurant_id,
      COUNT(*)::DOUBLE PRECISION * 3 AS score   -- strong signal
    FROM master_orders mo
    JOIN restaurant_orders ro1 ON ro1.master_order_id = mo.id
                               AND ro1.restaurant_id   = ANY(p_cart_restaurant_ids)
    JOIN restaurant_orders ro2 ON ro2.master_order_id = mo.id
                               AND ro2.restaurant_id  != ALL(p_cart_restaurant_ids)
    WHERE mo.customer_id = p_user_id
      AND mo.status IN ('delivered', 'completed')
    GROUP BY ro2.restaurant_id
  ),

  -- ── 2. General affinity: all restaurants the user has ever ordered from ──
  affinity_scores AS (
    SELECT
      restaurant_id,
      COUNT(*)::DOUBLE PRECISION AS score       -- weaker general signal
    FROM orders
    WHERE user_id      = p_user_id
      AND status       IN ('delivered', 'completed')
      AND restaurant_id IS NOT NULL
      AND restaurant_id != ALL(p_cart_restaurant_ids)
    GROUP BY restaurant_id
  ),

  -- ── 3. Combined behaviour score ────────────────────────────────────────────
  behaviour AS (
    SELECT
      COALESCE(co.restaurant_id, af.restaurant_id) AS restaurant_id,
      COALESCE(co.score, 0) + COALESCE(af.score, 0)  AS behavior_score,
      COALESCE(co.score, 0) >= 3                       AS is_co_order
    FROM      co_order_scores co
    FULL JOIN affinity_scores  af ON af.restaurant_id = co.restaurant_id
  ),

  -- ── 4. Join with restaurant metadata + distance scoring ───────────────────
  scored AS (
    SELECT
      r.id                       AS restaurant_id,
      r.name                     AS restaurant_name,
      r.cuisine_type,
      r.rating,
      r.image_url,
      r.estimated_delivery_time,
      r.delivery_fee,
      b.behavior_score,
      b.is_co_order,
      -- Haversine approximation (in km) when both sets of coords are available
      CASE
        WHEN p_delivery_lat IS NOT NULL AND p_delivery_lng IS NOT NULL
         AND r.latitude       IS NOT NULL AND r.longitude      IS NOT NULL
        THEN 6371.0 * 2 * ASIN(SQRT(
               POWER(SIN(RADIANS((r.latitude  - p_delivery_lat ) / 2)), 2) +
               COS(RADIANS(p_delivery_lat)) * COS(RADIANS(r.latitude)) *
               POWER(SIN(RADIANS((r.longitude - p_delivery_lng) / 2)), 2)
             ))
        ELSE NULL
      END                        AS distance_km,
      COALESCE(b.behavior_score, 0)
        -- proximity bonus: max 5 pts at 0 km, 0 pts at 10 km
        + CASE
            WHEN p_delivery_lat IS NOT NULL AND r.latitude IS NOT NULL
            THEN GREATEST(0,
                   10 - 6371.0 * 2 * ASIN(SQRT(
                         POWER(SIN(RADIANS((r.latitude  - p_delivery_lat ) / 2)), 2) +
                         COS(RADIANS(p_delivery_lat)) * COS(RADIANS(r.latitude)) *
                         POWER(SIN(RADIANS((r.longitude - p_delivery_lng) / 2)), 2)
                       ))
                 ) * 0.5
            ELSE 0
          END
        + COALESCE(r.rating, 3) * 0.3
                               AS final_score
    FROM behaviour b
    JOIN restaurants r ON r.id = b.restaurant_id
    WHERE r.is_open     = TRUE
      AND r.is_verified = TRUE
      AND r.id         != ALL(p_cart_restaurant_ids)
  )

  SELECT
    s.restaurant_id,
    s.restaurant_name,
    s.cuisine_type,
    s.rating,
    s.image_url,
    s.estimated_delivery_time,
    ROUND(s.distance_km::NUMERIC, 1)::DOUBLE PRECISION,
    s.delivery_fee,
    s.behavior_score,
    s.final_score,
    -- Human-readable reason
    CASE
      WHEN s.is_co_order
        THEN 'You often order from here with ' || COALESCE(v_cart_names, 'your other restaurants')
      ELSE 'One of your favourite spots nearby'
    END                         AS reason,
    s.is_co_order
  FROM scored s
  WHERE s.distance_km IS NULL OR s.distance_km <= p_max_distance_km
  ORDER BY
    s.is_co_order DESC,
    s.final_score  DESC
  LIMIT p_limit;

END;
$$;

GRANT EXECUTE ON FUNCTION public.get_cart_recommendations(UUID, UUID[], DOUBLE PRECISION, DOUBLE PRECISION, DOUBLE PRECISION, INT)
  TO authenticated, service_role;
