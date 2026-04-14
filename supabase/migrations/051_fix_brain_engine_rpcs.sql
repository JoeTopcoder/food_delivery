-- ====================================================================
-- 051: Fix brain engine RPCs
-- Fix type mismatch (numeric vs double precision) in get_smart_recommendations
-- Upgrade new-user coupon to 30%, improve section assignment for new users
-- ====================================================================

-- 1. Fix get_smart_recommendations: cast distance_km and final_score to DOUBLE PRECISION
CREATE OR REPLACE FUNCTION public.get_smart_recommendations(
  p_user_id UUID,
  p_latitude DOUBLE PRECISION DEFAULT NULL,
  p_longitude DOUBLE PRECISION DEFAULT NULL,
  p_limit INT DEFAULT 20
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
  v_is_new_user BOOLEAN;
BEGIN
  -- Get or create user profile
  PERFORM public.compute_user_profile(p_user_id);

  SELECT * INTO v_profile
  FROM public.user_intelligence_profiles
  WHERE user_id = p_user_id;

  v_hour := EXTRACT(HOUR FROM NOW())::INT;
  v_is_new_user := (v_profile.user_segment = 'new_user');

  -- Get top cuisine for the user
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
      -- Distance calculation (Haversine approximation in km)
      (CASE WHEN p_latitude IS NOT NULL AND p_longitude IS NOT NULL
           AND r.latitude IS NOT NULL AND r.longitude IS NOT NULL
      THEN (
        6371.0 * acos(
          LEAST(1.0, GREATEST(-1.0,
            cos(radians(p_latitude)) * cos(radians(r.latitude)) *
            cos(radians(r.longitude) - radians(p_longitude)) +
            sin(radians(p_latitude)) * sin(radians(r.latitude))
          ))
        )
      )
      ELSE 999.0
      END)::DOUBLE PRECISION AS distance_km,
      -- SCORING ENGINE
      (
        -- Base rating score (0-1 normalized)
        (COALESCE(r.rating, 0) / 5.0) * 0.20
        +
        -- Cuisine match score (new users get neutral boost for all cuisines)
        CASE WHEN v_is_new_user THEN 0.12
             WHEN r.cuisine_type IS NOT NULL
                  AND v_profile.cuisine_scores ? r.cuisine_type
             THEN (v_profile.cuisine_scores->>r.cuisine_type)::FLOAT * 0.25
             ELSE 0.05
        END
        +
        -- Price match (lower delivery fee = better match for price-sensitive)
        CASE WHEN v_profile.price_sensitivity > 0.6
             AND COALESCE(r.delivery_fee, 50) < 60
        THEN 0.15
        WHEN v_profile.price_sensitivity <= 0.6 THEN 0.10
        ELSE 0.05
        END
        +
        -- Distance score (closer = higher)
        CASE WHEN p_latitude IS NOT NULL AND r.latitude IS NOT NULL
        THEN GREATEST(0, 0.15 - (
          6371 * acos(
            LEAST(1.0, GREATEST(-1.0,
              cos(radians(p_latitude)) * cos(radians(r.latitude)) *
              cos(radians(r.longitude) - radians(p_longitude)) +
              sin(radians(p_latitude)) * sin(radians(r.latitude))
            ))
          ) / 25.0 * 0.15
        ))
        ELSE 0.05
        END
        +
        -- Time-of-day boost
        CASE
          WHEN v_hour BETWEEN 6 AND 10
               AND r.cuisine_type ILIKE '%breakfast%' THEN 0.10
          WHEN v_hour BETWEEN 11 AND 14
               AND r.cuisine_type IN ('Fast Food', 'Bengali', 'Bangladeshi') THEN 0.08
          WHEN v_hour BETWEEN 20 AND 23
               AND r.cuisine_type IN ('Pizza', 'Fast Food', 'Chinese') THEN 0.10
          ELSE 0.03
        END
        +
        -- Popularity / review count boost (higher for new users)
        CASE WHEN v_is_new_user AND COALESCE(r.rating, 0) >= 4.0 THEN 0.12
             WHEN COALESCE(r.review_count, 0) > 50 THEN 0.10
             WHEN COALESCE(r.review_count, 0) > 20 THEN 0.07
             ELSE 0.03
        END
        +
        -- Open restaurant boost
        CASE WHEN r.is_open THEN 0.05 ELSE -0.20 END
      )::DOUBLE PRECISION AS final_score,
      -- Section assignment (new users get "for_you" and "quick_delivery" only)
      CASE
        WHEN NOT v_is_new_user
             AND r.cuisine_type IS NOT NULL
             AND v_profile.cuisine_scores ? r.cuisine_type
             AND (v_profile.cuisine_scores->>r.cuisine_type)::FLOAT > 0.3
        THEN 'because_you_love'
        WHEN NOT v_is_new_user
             AND v_profile.deal_sensitivity > 0.6
             AND COALESCE(r.delivery_fee, 50) < 40
        THEN 'deals_for_you'
        WHEN COALESCE(r.estimated_delivery_time, 60) <= 30
        THEN 'quick_delivery'
        ELSE 'for_you'
      END AS section,
      -- Reason text
      CASE
        WHEN v_is_new_user AND COALESCE(r.rating, 0) >= 4.0
        THEN 'Popular with our customers'
        WHEN v_is_new_user
        THEN 'Great place to start'
        WHEN r.cuisine_type IS NOT NULL AND r.cuisine_type = v_top_cuisine
        THEN 'Because you love ' || r.cuisine_type
        WHEN COALESCE(r.rating, 0) >= 4.5
        THEN 'Highly rated near you'
        WHEN COALESCE(r.estimated_delivery_time, 60) <= 25
        THEN 'Quick delivery available'
        ELSE 'Recommended for you'
      END AS reason
    FROM public.restaurants r
    WHERE r.is_verified = TRUE
  )
  SELECT * FROM scored
  ORDER BY scored.final_score DESC
  LIMIT p_limit;
END;
$$;

-- 2. Fix generate_targeted_coupon: 30% for new users, always generate for new users
CREATE OR REPLACE FUNCTION public.generate_targeted_coupon(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_profile RECORD;
  v_code TEXT;
  v_discount INT;
  v_reason TEXT;
  v_coupon_id UUID;
  v_min_order DOUBLE PRECISION;
BEGIN
  SELECT * INTO v_profile
  FROM public.user_intelligence_profiles
  WHERE user_id = p_user_id;

  IF v_profile IS NULL THEN
    PERFORM public.compute_user_profile(p_user_id);
    SELECT * INTO v_profile
    FROM public.user_intelligence_profiles
    WHERE user_id = p_user_id;
  END IF;

  -- Don't generate if user already has an active coupon
  IF EXISTS (
    SELECT 1 FROM public.user_coupons
    WHERE user_id = p_user_id
      AND is_used = FALSE
      AND expires_at > NOW()
  ) THEN
    -- Return the existing active coupon details instead of nothing
    RETURN (
      SELECT jsonb_build_object(
        'generated', TRUE,
        'coupon_id', c.id,
        'code', c.code,
        'discount_percent', c.discount_percent::INT,
        'reason', c.reason,
        'min_order', c.min_order,
        'expires_in_hours', GREATEST(1, EXTRACT(EPOCH FROM c.expires_at - NOW())::INT / 3600)
      )
      FROM public.user_coupons c
      WHERE c.user_id = p_user_id
        AND c.is_used = FALSE
        AND c.expires_at > NOW()
      ORDER BY c.created_at DESC
      LIMIT 1
    );
  END IF;

  -- Determine discount based on segment and churn risk
  IF v_profile.user_segment = 'new_user' THEN
    v_discount := 30;
    v_reason := 'Welcome to MealHub! Save 30% on your first order';
    v_min_order := 0;
  ELSIF v_profile.churn_risk > 0.8 THEN
    v_discount := 35;
    v_reason := 'We miss you! Here''s a special deal';
    v_min_order := 200;
  ELSIF v_profile.churn_risk > 0.6 THEN
    v_discount := 20;
    v_reason := 'It''s been a while - treat yourself!';
    v_min_order := 150;
  ELSIF v_profile.user_segment = 'power_user' THEN
    v_discount := 10;
    v_reason := 'Thanks for being a loyal customer!';
    v_min_order := 300;
  ELSE
    v_discount := 15;
    v_reason := 'A little treat just for you';
    v_min_order := 200;
  END IF;

  -- Generate unique code
  v_code := 'MEAL' || UPPER(SUBSTR(gen_random_uuid()::TEXT, 1, 6));

  INSERT INTO public.user_coupons (
    user_id, code, discount_percent, min_order, reason, expires_at
  ) VALUES (
    p_user_id, v_code, v_discount, v_min_order, v_reason,
    NOW() + INTERVAL '7 days'
  ) RETURNING id INTO v_coupon_id;

  RETURN jsonb_build_object(
    'generated', TRUE,
    'coupon_id', v_coupon_id,
    'code', v_code,
    'discount_percent', v_discount,
    'reason', v_reason,
    'min_order', v_min_order,
    'expires_in_hours', 168
  );
END;
$$;

-- 3. Enable RLS and add policies for new tables
ALTER TABLE public.user_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_intelligence_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_recommendations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_coupons ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_own_events" ON public.user_events
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

CREATE POLICY "users_own_profile" ON public.user_intelligence_profiles
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "users_own_recommendations" ON public.ai_recommendations
  FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "users_own_coupons" ON public.user_coupons
  FOR ALL TO authenticated USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
