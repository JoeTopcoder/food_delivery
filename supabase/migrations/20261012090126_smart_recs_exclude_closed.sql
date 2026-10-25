-- get_smart_recommendations: exclude closed restaurants (is_open = FALSE) from
-- Made for You / recommendation sections, matching browse-listing behaviour.

CREATE OR REPLACE FUNCTION public.get_smart_recommendations(p_user_id uuid, p_latitude double precision DEFAULT NULL::double precision, p_longitude double precision DEFAULT NULL::double precision, p_limit integer DEFAULT 30)
 RETURNS TABLE(restaurant_id uuid, restaurant_name text, cuisine_type text, rating double precision, image_url text, delivery_fee double precision, estimated_delivery_time integer, is_open boolean, distance_km double precision, final_score double precision, section text, reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
      COALESCE(r.rating, 0)::DOUBLE PRECISION AS rating,
      r.image_url,
      COALESCE(r.delivery_fee, 0)::DOUBLE PRECISION AS delivery_fee,
      r.estimated_delivery_time,
      r.is_open,
      (CASE WHEN p_latitude IS NOT NULL AND p_longitude IS NOT NULL
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
      END)::DOUBLE PRECISION AS distance_km,
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
      )::DOUBLE PRECISION AS final_score,
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
      AND r.is_open = TRUE
      AND COALESCE(r.store_type, 'food') != 'grocery'
  )
  SELECT * FROM scored
  ORDER BY scored.final_score DESC
  LIMIT p_limit;
END;
$function$;

NOTIFY pgrst, 'reload schema';
