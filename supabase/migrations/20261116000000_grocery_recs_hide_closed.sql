-- "Stores for You" (grocery Brain Engine) was showing closed grocery stores.
-- get_grocery_recommendations only PENALIZED a closed store in its score
-- (is_open ? +0.10 : -0.20) but never excluded it, so a store closed by its
-- owner (is_open = false) still appeared in the recommendation rails. Match the
-- rest of the grocery surfaces (getGroceryStores etc.) and hide closed stores
-- entirely by filtering them out in the WHERE clause.
CREATE OR REPLACE FUNCTION public.get_grocery_recommendations(p_user_id uuid, p_latitude double precision DEFAULT NULL::double precision, p_longitude double precision DEFAULT NULL::double precision, p_limit integer DEFAULT 30)
 RETURNS TABLE(restaurant_id uuid, restaurant_name text, cuisine_type text, rating double precision, image_url text, delivery_fee double precision, estimated_delivery_time integer, is_open boolean, distance_km double precision, final_score double precision, section text, reason text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_profile RECORD;
  v_hour INT;
BEGIN
  p_user_id := COALESCE(auth.uid(), p_user_id);  -- pin to caller (IDOR fix)
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
        (COALESCE(r.rating, 0) / 5.0) * 0.25
        + CASE WHEN p_latitude IS NOT NULL AND r.latitude IS NOT NULL
          THEN GREATEST(0, 0.25 - (
            6371 * acos(LEAST(1.0, GREATEST(-1.0,
              cos(radians(p_latitude)) * cos(radians(r.latitude)) *
              cos(radians(r.longitude) - radians(p_longitude)) +
              sin(radians(p_latitude)) * sin(radians(r.latitude))
            ))) / 25.0 * 0.25))
          ELSE 0.05 END
        + CASE WHEN v_profile.deal_sensitivity > 0.6
               AND COALESCE(r.delivery_fee, 50) < 40 THEN 0.15
          WHEN v_profile.price_sensitivity > 0.6 THEN 0.10
          ELSE 0.05 END
        + CASE WHEN COALESCE(r.review_count, 0) > 50 THEN 0.15
               WHEN COALESCE(r.review_count, 0) > 20 THEN 0.10
               ELSE 0.03 END
        + CASE WHEN r.is_open THEN 0.10 ELSE -0.20 END
      )::DOUBLE PRECISION AS final_score,
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
      CASE
        WHEN COALESCE(r.rating, 0) >= 4.5 THEN 'Top rated grocery store'
        WHEN COALESCE(r.estimated_delivery_time, 60) <= 25 THEN 'Quick delivery available'
        WHEN COALESCE(r.delivery_fee, 50) < 40 THEN 'Great deals on delivery'
        ELSE 'Recommended for you'
      END AS reason
    FROM public.restaurants r
    WHERE r.is_verified = TRUE
      AND r.is_open = TRUE                       -- hide closed stores entirely
      AND r.store_type IN ('grocery', 'both')
  )
  SELECT * FROM scored
  ORDER BY scored.final_score DESC
  LIMIT p_limit;
END;
$function$;

NOTIFY pgrst, 'reload schema';
