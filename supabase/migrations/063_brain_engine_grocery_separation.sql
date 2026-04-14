-- ====================================================================
-- Filter grocery stores from food brain engine, add grocery brain engine
-- ====================================================================

-- 1. Update get_smart_recommendations to exclude grocery-only stores
CREATE OR REPLACE FUNCTION public.get_smart_recommendations(
  p_user_id UUID,
  p_latitude DOUBLE PRECISION DEFAULT NULL,
  p_longitude DOUBLE PRECISION DEFAULT NULL,
  p_limit INT DEFAULT 30
)
RETURNS TABLE(
  restaurant_id UUID,
  restaurant_name TEXT,
  cuisine_type TEXT,
  rating DOUBLE PRECISION,
  image_url TEXT,
  delivery_fee DOUBLE PRECISION,
  estimated_delivery_time INT,
  is_open BOOLEAN,
  distance_km DOUBLE PRECISION,
  final_score DOUBLE PRECISION,
  section TEXT,
  reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_profile RECORD;
  v_hour INT;
  v_top_cuisine TEXT;
BEGIN
  PERFORM public.compute_user_profile(p_user_id);

  SELECT * INTO v_profile
  FROM public.user_intelligence_profiles
  WHERE user_id = p_user_id;

  v_hour := EXTRACT(HOUR FROM NOW())::INT;

  SELECT key INTO v_top_cuisine
  FROM jsonb_each_text(COALESCE(v_profile.cuisine_scores, '{}'))
  ORDER BY value::NUMERIC DESC
  LIMIT 1;

  RETURN QUERY
  WITH scored AS (
    SELECT
      r.id AS restaurant_id,
      r.name AS restaurant_name,
      r.cuisine_type,
      COALESCE(r.rating, 0) AS rating,
      r.image_url,
      COALESCE(r.delivery_fee, 0) AS delivery_fee,
      r.estimated_delivery_time,
      r.is_open,
      CASE WHEN p_latitude IS NOT NULL AND p_longitude IS NOT NULL
           AND r.latitude IS NOT NULL AND r.longitude IS NOT NULL
      THEN ROUND((
        6371 * acos(
          LEAST(1.0, GREATEST(-1.0,
            cos(radians(p_latitude)) * cos(radians(r.latitude)) *
            cos(radians(r.longitude) - radians(p_longitude)) +
            sin(radians(p_latitude)) * sin(radians(r.latitude))
          ))
        )
      )::NUMERIC, 2)
      ELSE 999.0
      END AS distance_km,
      (
        (COALESCE(r.rating, 0) / 5.0) * 0.20
        + CASE WHEN r.cuisine_type IS NOT NULL
               AND v_profile.cuisine_scores ? r.cuisine_type
          THEN (v_profile.cuisine_scores->>r.cuisine_type)::NUMERIC * 0.25
          ELSE 0.05 END
        + CASE WHEN v_profile.price_sensitivity > 0.6
               AND COALESCE(r.delivery_fee, 50) < 60 THEN 0.15
          WHEN v_profile.price_sensitivity <= 0.6 THEN 0.10
          ELSE 0.05 END
        + CASE WHEN p_latitude IS NOT NULL AND r.latitude IS NOT NULL
          THEN GREATEST(0, 0.15 - (
            6371 * acos(LEAST(1.0, GREATEST(-1.0,
              cos(radians(p_latitude)) * cos(radians(r.latitude)) *
              cos(radians(r.longitude) - radians(p_longitude)) +
              sin(radians(p_latitude)) * sin(radians(r.latitude))
            ))) / 25.0 * 0.15))
          ELSE 0.05 END
        + CASE
            WHEN v_hour BETWEEN 6 AND 10 AND r.cuisine_type ILIKE '%breakfast%' THEN 0.10
            WHEN v_hour BETWEEN 11 AND 14 AND r.cuisine_type IN ('Fast Food','Bengali','Bangladeshi') THEN 0.08
            WHEN v_hour BETWEEN 20 AND 23 AND r.cuisine_type IN ('Pizza','Fast Food','Chinese') THEN 0.10
            ELSE 0.03 END
        + CASE WHEN COALESCE(r.review_count, 0) > 50 THEN 0.10
               WHEN COALESCE(r.review_count, 0) > 20 THEN 0.07
               ELSE 0.03 END
        + CASE WHEN r.is_open THEN 0.05 ELSE -0.20 END
      ) AS final_score,
      CASE
        WHEN r.cuisine_type IS NOT NULL
             AND v_profile.cuisine_scores ? r.cuisine_type
             AND (v_profile.cuisine_scores->>r.cuisine_type)::NUMERIC > 0.3
        THEN 'because_you_love'
        WHEN v_profile.deal_sensitivity > 0.6
             AND COALESCE(r.delivery_fee, 50) < 40
        THEN 'deals_for_you'
        WHEN COALESCE(r.estimated_delivery_time, 60) <= 25
        THEN 'quick_delivery'
        ELSE 'for_you'
      END AS section,
      CASE
        WHEN r.cuisine_type IS NOT NULL AND r.cuisine_type = v_top_cuisine
        THEN 'Because you love ' || r.cuisine_type
        WHEN COALESCE(r.rating, 0) >= 4.5 THEN 'Highly rated near you'
        WHEN COALESCE(r.estimated_delivery_time, 60) <= 25 THEN 'Quick delivery available'
        ELSE 'Recommended for you'
      END AS reason
    FROM public.restaurants r
    WHERE r.is_verified = TRUE
      AND COALESCE(r.store_type, 'food') != 'grocery'
  )
  SELECT * FROM scored
  ORDER BY scored.final_score DESC
  LIMIT p_limit;
END;
$$;

-- 2. Create grocery-specific brain engine
CREATE OR REPLACE FUNCTION public.get_grocery_recommendations(
  p_user_id UUID,
  p_latitude DOUBLE PRECISION DEFAULT NULL,
  p_longitude DOUBLE PRECISION DEFAULT NULL,
  p_limit INT DEFAULT 30
)
RETURNS TABLE(
  restaurant_id UUID,
  restaurant_name TEXT,
  cuisine_type TEXT,
  rating DOUBLE PRECISION,
  image_url TEXT,
  delivery_fee DOUBLE PRECISION,
  estimated_delivery_time INT,
  is_open BOOLEAN,
  distance_km DOUBLE PRECISION,
  final_score DOUBLE PRECISION,
  section TEXT,
  reason TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_profile RECORD;
  v_hour INT;
BEGIN
  PERFORM public.compute_user_profile(p_user_id);

  SELECT * INTO v_profile
  FROM public.user_intelligence_profiles
  WHERE user_id = p_user_id;

  v_hour := EXTRACT(HOUR FROM NOW())::INT;

  RETURN QUERY
  WITH scored AS (
    SELECT
      r.id AS restaurant_id,
      r.name AS restaurant_name,
      r.cuisine_type,
      COALESCE(r.rating, 0) AS rating,
      r.image_url,
      COALESCE(r.delivery_fee, 0) AS delivery_fee,
      r.estimated_delivery_time,
      r.is_open,
      CASE WHEN p_latitude IS NOT NULL AND p_longitude IS NOT NULL
           AND r.latitude IS NOT NULL AND r.longitude IS NOT NULL
      THEN ROUND((
        6371 * acos(
          LEAST(1.0, GREATEST(-1.0,
            cos(radians(p_latitude)) * cos(radians(r.latitude)) *
            cos(radians(r.longitude) - radians(p_longitude)) +
            sin(radians(p_latitude)) * sin(radians(r.latitude))
          ))
        )
      )::NUMERIC, 2)
      ELSE 999.0
      END AS distance_km,
      (
        -- Rating
        (COALESCE(r.rating, 0) / 5.0) * 0.25
        -- Distance (closer = higher)
        + CASE WHEN p_latitude IS NOT NULL AND r.latitude IS NOT NULL
          THEN GREATEST(0, 0.25 - (
            6371 * acos(LEAST(1.0, GREATEST(-1.0,
              cos(radians(p_latitude)) * cos(radians(r.latitude)) *
              cos(radians(r.longitude) - radians(p_longitude)) +
              sin(radians(p_latitude)) * sin(radians(r.latitude))
            ))) / 25.0 * 0.25))
          ELSE 0.05 END
        -- Deal sensitivity (low delivery fee)
        + CASE WHEN v_profile.deal_sensitivity > 0.6
               AND COALESCE(r.delivery_fee, 50) < 40 THEN 0.15
          WHEN v_profile.price_sensitivity > 0.6 THEN 0.10
          ELSE 0.05 END
        -- Popularity
        + CASE WHEN COALESCE(r.review_count, 0) > 50 THEN 0.15
               WHEN COALESCE(r.review_count, 0) > 20 THEN 0.10
               ELSE 0.03 END
        -- Open store boost
        + CASE WHEN r.is_open THEN 0.10 ELSE -0.20 END
      ) AS final_score,
      -- Section assignment for grocery
      CASE
        WHEN v_profile.deal_sensitivity > 0.6
             AND COALESCE(r.delivery_fee, 50) < 40
        THEN 'deals_for_you'
        WHEN COALESCE(r.estimated_delivery_time, 60) <= 25
        THEN 'quick_delivery'
        WHEN COALESCE(r.rating, 0) >= 4.5
        THEN 'because_you_love'
        ELSE 'for_you'
      END AS section,
      -- Reason text
      CASE
        WHEN COALESCE(r.rating, 0) >= 4.5 THEN 'Top rated grocery store'
        WHEN COALESCE(r.estimated_delivery_time, 60) <= 25 THEN 'Quick delivery available'
        WHEN COALESCE(r.delivery_fee, 50) < 40 THEN 'Great deals on delivery'
        ELSE 'Recommended for you'
      END AS reason
    FROM public.restaurants r
    WHERE r.is_verified = TRUE
      AND r.store_type IN ('grocery', 'both')
  )
  SELECT * FROM scored
  ORDER BY scored.final_score DESC
  LIMIT p_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_grocery_recommendations(UUID, DOUBLE PRECISION, DOUBLE PRECISION, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_grocery_recommendations(UUID, DOUBLE PRECISION, DOUBLE PRECISION, INT) TO anon;

-- 3. Update search_menu_items to exclude grocery products in food search
CREATE OR REPLACE FUNCTION public.search_menu_items(
  p_query TEXT DEFAULT NULL,
  p_cuisine TEXT DEFAULT NULL,
  p_max_price DECIMAL DEFAULT NULL,
  p_min_rating DECIMAL DEFAULT NULL,
  p_limit INT DEFAULT 50
)
RETURNS TABLE(
  item_id UUID,
  item_name TEXT,
  item_description TEXT,
  item_price DECIMAL,
  item_image_url TEXT,
  item_category TEXT,
  item_discount DECIMAL,
  restaurant_id UUID,
  restaurant_name TEXT,
  restaurant_image TEXT,
  restaurant_rating DECIMAL,
  restaurant_cuisine TEXT,
  rank REAL
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT
    m.id AS item_id,
    m.name AS item_name,
    m.description AS item_description,
    m.price AS item_price,
    m.image_url AS item_image_url,
    m.category AS item_category,
    m.discount AS item_discount,
    r.id AS restaurant_id,
    r.name AS restaurant_name,
    r.image_url AS restaurant_image,
    r.rating AS restaurant_rating,
    r.cuisine_type AS restaurant_cuisine,
    CASE
      WHEN p_query IS NOT NULL AND p_query != '' THEN
        ts_rank(m.search_vector, plainto_tsquery('english', p_query))
      ELSE 1.0
    END::REAL AS rank
  FROM menus m
  JOIN restaurants r ON r.id = m.restaurant_id
  WHERE m.is_available = true
    AND COALESCE(m.product_type, 'food') != 'grocery'
    AND COALESCE(r.store_type, 'food') != 'grocery'
    AND (p_query IS NULL OR p_query = '' OR m.search_vector @@ plainto_tsquery('english', p_query)
         OR m.name ILIKE '%' || p_query || '%')
    AND (p_cuisine IS NULL OR r.cuisine_type ILIKE '%' || p_cuisine || '%')
    AND (p_max_price IS NULL OR m.price <= p_max_price)
    AND (p_min_rating IS NULL OR r.rating >= p_min_rating)
  ORDER BY rank DESC, m.name
  LIMIT p_limit;
END;
$$;

-- 4. Update get_recommendations to exclude grocery products
CREATE OR REPLACE FUNCTION public.get_recommendations(p_user_id UUID, p_limit INT DEFAULT 20)
RETURNS TABLE(
  item_id UUID,
  item_name TEXT,
  item_price DECIMAL,
  item_image_url TEXT,
  restaurant_id UUID,
  restaurant_name TEXT,
  restaurant_image TEXT,
  score REAL
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  WITH user_cuisines AS (
    SELECT DISTINCT r.cuisine_type
    FROM orders o
    JOIN restaurants r ON r.id = o.restaurant_id
    WHERE o.user_id = p_user_id AND o.status = 'delivered'
  ),
  user_ordered_items AS (
    SELECT DISTINCT oi.menu_item_id
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.user_id = p_user_id
  )
  SELECT
    m.id AS item_id,
    m.name AS item_name,
    m.price AS item_price,
    m.image_url AS item_image_url,
    r.id AS restaurant_id,
    r.name AS restaurant_name,
    r.image_url AS restaurant_image,
    (COALESCE(r.rating, 3.0) * 0.6 + RANDOM()::NUMERIC * 2)::REAL AS score
  FROM menus m
  JOIN restaurants r ON r.id = m.restaurant_id
  WHERE m.is_available = true
    AND r.is_open = true
    AND COALESCE(m.product_type, 'food') != 'grocery'
    AND COALESCE(r.store_type, 'food') != 'grocery'
    AND (
      r.cuisine_type IN (SELECT cuisine_type FROM user_cuisines)
      OR r.rating >= 4.0
    )
    AND m.id NOT IN (SELECT menu_item_id FROM user_ordered_items WHERE menu_item_id IS NOT NULL)
  ORDER BY score DESC
  LIMIT p_limit;
END;
$$;
