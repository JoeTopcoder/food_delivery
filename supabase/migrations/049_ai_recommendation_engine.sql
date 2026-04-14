-- ====================================================================
-- AI RECOMMENDATION ENGINE - COMPLETE SCHEMA
-- Tables: user_events, user_intelligence_profiles, restaurant_embeddings,
--         ai_recommendations, user_coupons
-- ====================================================================

-- Enable pgvector extension for embedding similarity search
CREATE EXTENSION IF NOT EXISTS vector;

-- ====================================================================
-- 1. USER EVENTS - Track every user interaction
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.user_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  event_type TEXT NOT NULL,
  metadata JSONB DEFAULT '{}',
  session_id TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_events_user_id ON public.user_events(user_id);
CREATE INDEX idx_user_events_event_type ON public.user_events(event_type);
CREATE INDEX idx_user_events_created_at ON public.user_events(created_at);
CREATE INDEX idx_user_events_user_recent ON public.user_events(user_id, created_at DESC);

-- ====================================================================
-- 2. USER INTELLIGENCE PROFILES - Behavioral DNA
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.user_intelligence_profiles (
  user_id UUID PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  taste_profile JSONB DEFAULT '{}',
  cuisine_scores JSONB DEFAULT '{}',
  price_sensitivity DOUBLE PRECISION DEFAULT 0.5,
  deal_sensitivity DOUBLE PRECISION DEFAULT 0.5,
  avg_order_value DOUBLE PRECISION DEFAULT 0,
  order_frequency DOUBLE PRECISION DEFAULT 0,
  preferred_order_times JSONB DEFAULT '{}',
  order_habit JSONB DEFAULT '{}',
  favorite_categories JSONB DEFAULT '[]',
  churn_risk DOUBLE PRECISION DEFAULT 0,
  user_segment TEXT DEFAULT 'new_user',
  total_orders INTEGER DEFAULT 0,
  days_since_last_order INTEGER DEFAULT 0,
  activity_score DOUBLE PRECISION DEFAULT 0,
  embedding vector(1536),
  summary_text TEXT,
  last_computed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_uip_user_segment ON public.user_intelligence_profiles(user_segment);
CREATE INDEX idx_uip_churn_risk ON public.user_intelligence_profiles(churn_risk);

-- ====================================================================
-- 3. RESTAURANT EMBEDDINGS - For vector matching
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.restaurant_embeddings (
  restaurant_id UUID PRIMARY KEY REFERENCES public.restaurants(id) ON DELETE CASCADE,
  embedding vector(1536),
  summary_text TEXT,
  cuisine_tags JSONB DEFAULT '[]',
  price_tier INTEGER DEFAULT 2,
  avg_rating DOUBLE PRECISION DEFAULT 0,
  popularity_score DOUBLE PRECISION DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ====================================================================
-- 4. AI RECOMMENDATIONS - Cached per-user recommendations
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.ai_recommendations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  score DOUBLE PRECISION NOT NULL DEFAULT 0,
  reason TEXT,
  section TEXT NOT NULL DEFAULT 'for_you',
  rank INTEGER DEFAULT 0,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() + INTERVAL '6 hours'),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ai_rec_user ON public.ai_recommendations(user_id);
CREATE INDEX idx_ai_rec_section ON public.ai_recommendations(section);
CREATE INDEX idx_ai_rec_expires ON public.ai_recommendations(expires_at);
CREATE UNIQUE INDEX idx_ai_rec_unique ON public.ai_recommendations(user_id, restaurant_id, section);

-- ====================================================================
-- 5. USER COUPONS - AI-generated targeted coupons
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.user_coupons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  discount_percent DOUBLE PRECISION DEFAULT 0,
  discount_amount DOUBLE PRECISION DEFAULT 0,
  min_order DOUBLE PRECISION DEFAULT 0,
  reason TEXT,
  restaurant_id UUID REFERENCES public.restaurants(id) ON DELETE SET NULL,
  is_used BOOLEAN DEFAULT FALSE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_coupons_user ON public.user_coupons(user_id);
CREATE INDEX idx_user_coupons_active ON public.user_coupons(user_id, is_used, expires_at);

-- ====================================================================
-- 6. RPC: Compute user intelligence profile from events & orders
-- ====================================================================
CREATE OR REPLACE FUNCTION public.compute_user_profile(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_orders INT;
  v_days_since INT;
  v_avg_order DOUBLE PRECISION;
  v_cuisine_scores JSONB;
  v_time_prefs JSONB;
  v_price_sensitivity DOUBLE PRECISION;
  v_deal_sensitivity DOUBLE PRECISION;
  v_churn_risk DOUBLE PRECISION;
  v_segment TEXT;
  v_activity DOUBLE PRECISION;
  v_order_freq DOUBLE PRECISION;
  v_fav_cats JSONB;
BEGIN
  -- Total completed orders
  SELECT COUNT(*) INTO v_total_orders
  FROM public.orders
  WHERE user_id = p_user_id AND status = 'delivered';

  -- Days since last order
  SELECT COALESCE(
    EXTRACT(DAY FROM NOW() - MAX(completed_at))::INT, 999
  ) INTO v_days_since
  FROM public.orders
  WHERE user_id = p_user_id AND status = 'delivered';

  -- Average order value
  SELECT COALESCE(AVG(total_amount), 0) INTO v_avg_order
  FROM public.orders
  WHERE user_id = p_user_id AND status = 'delivered';

  -- Cuisine scores from recent orders (last 90 days)
  SELECT COALESCE(jsonb_object_agg(cuisine, score), '{}')
  INTO v_cuisine_scores
  FROM (
    SELECT r.cuisine_type AS cuisine,
           ROUND((COUNT(*)::NUMERIC / GREATEST(v_total_orders, 1)), 2) AS score
    FROM public.orders o
    JOIN public.restaurants r ON o.restaurant_id = r.id
    WHERE o.user_id = p_user_id
      AND o.status = 'delivered'
      AND o.completed_at > NOW() - INTERVAL '90 days'
      AND r.cuisine_type IS NOT NULL
    GROUP BY r.cuisine_type
    ORDER BY COUNT(*) DESC
    LIMIT 10
  ) sub;

  -- Time preferences (hour distribution)
  SELECT COALESCE(jsonb_object_agg(hr, cnt), '{}')
  INTO v_time_prefs
  FROM (
    SELECT EXTRACT(HOUR FROM ordered_at)::TEXT AS hr, COUNT(*) AS cnt
    FROM public.orders
    WHERE user_id = p_user_id AND status = 'delivered'
    GROUP BY hr
  ) sub;

  -- Price sensitivity: ratio of orders with discount vs total
  SELECT COALESCE(
    ROUND(COUNT(*) FILTER (WHERE discount > 0)::NUMERIC / GREATEST(COUNT(*), 1), 2),
    0.5
  ) INTO v_price_sensitivity
  FROM public.orders
  WHERE user_id = p_user_id AND status = 'delivered';

  -- Deal sensitivity: ratio of promo-related events
  SELECT COALESCE(
    ROUND(
      COUNT(*) FILTER (WHERE event_type IN ('coupon_applied', 'deal_clicked', 'promo_viewed'))::NUMERIC
      / GREATEST(COUNT(*), 1), 2
    ), 0.5
  ) INTO v_deal_sensitivity
  FROM public.user_events
  WHERE user_id = p_user_id
    AND created_at > NOW() - INTERVAL '30 days';

  -- Order frequency (orders per week over last 30 days)
  SELECT COALESCE(
    ROUND(COUNT(*)::NUMERIC / 4.0, 2), 0
  ) INTO v_order_freq
  FROM public.orders
  WHERE user_id = p_user_id
    AND status = 'delivered'
    AND ordered_at > NOW() - INTERVAL '30 days';

  -- Activity score from events (last 7 days normalized)
  SELECT COALESCE(LEAST(COUNT(*)::NUMERIC / 50.0, 1.0), 0)
  INTO v_activity
  FROM public.user_events
  WHERE user_id = p_user_id
    AND created_at > NOW() - INTERVAL '7 days';

  -- Churn risk calculation
  v_churn_risk := LEAST(1.0, GREATEST(0.0,
    (LEAST(v_days_since, 30)::NUMERIC / 30.0) * 0.4 +
    (1.0 - v_activity) * 0.3 +
    CASE WHEN v_order_freq < 0.5 THEN 0.3 ELSE 0 END
  ));

  -- User segmentation
  IF v_total_orders = 0 THEN
    v_segment := 'new_user';
  ELSIF v_days_since > 14 THEN
    v_segment := 'inactive';
  ELSIF v_total_orders > 10 AND v_order_freq >= 1.5 THEN
    v_segment := 'power_user';
  ELSIF v_total_orders > 3 THEN
    v_segment := 'regular';
  ELSE
    v_segment := 'casual';
  END IF;

  -- Favorite categories
  SELECT COALESCE(jsonb_agg(cat), '[]')
  INTO v_fav_cats
  FROM (
    SELECT m.category AS cat
    FROM public.order_items oi
    JOIN public.orders o ON oi.order_id = o.id
    JOIN public.menus m ON oi.menu_item_id = m.id
    WHERE o.user_id = p_user_id AND o.status = 'delivered'
    GROUP BY m.category
    ORDER BY COUNT(*) DESC
    LIMIT 5
  ) sub;

  -- Upsert the profile
  INSERT INTO public.user_intelligence_profiles (
    user_id, cuisine_scores, price_sensitivity, deal_sensitivity,
    avg_order_value, order_frequency, preferred_order_times,
    favorite_categories, churn_risk, user_segment, total_orders,
    days_since_last_order, activity_score, last_computed_at, updated_at
  ) VALUES (
    p_user_id, v_cuisine_scores, v_price_sensitivity, v_deal_sensitivity,
    v_avg_order, v_order_freq, v_time_prefs,
    v_fav_cats, v_churn_risk, v_segment, v_total_orders,
    v_days_since, v_activity, NOW(), NOW()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    cuisine_scores = EXCLUDED.cuisine_scores,
    price_sensitivity = EXCLUDED.price_sensitivity,
    deal_sensitivity = EXCLUDED.deal_sensitivity,
    avg_order_value = EXCLUDED.avg_order_value,
    order_frequency = EXCLUDED.order_frequency,
    preferred_order_times = EXCLUDED.preferred_order_times,
    favorite_categories = EXCLUDED.favorite_categories,
    churn_risk = EXCLUDED.churn_risk,
    user_segment = EXCLUDED.user_segment,
    total_orders = EXCLUDED.total_orders,
    days_since_last_order = EXCLUDED.days_since_last_order,
    activity_score = EXCLUDED.activity_score,
    last_computed_at = NOW(),
    updated_at = NOW();

  RETURN jsonb_build_object(
    'user_id', p_user_id,
    'segment', v_segment,
    'churn_risk', v_churn_risk,
    'total_orders', v_total_orders,
    'days_since_last_order', v_days_since,
    'cuisine_scores', v_cuisine_scores,
    'price_sensitivity', v_price_sensitivity,
    'deal_sensitivity', v_deal_sensitivity,
    'order_frequency', v_order_freq,
    'activity_score', v_activity
  );
END;
$$;

-- ====================================================================
-- 7. RPC: Get smart recommendations (scoring engine)
-- ====================================================================
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
BEGIN
  -- Get or create user profile
  PERFORM public.compute_user_profile(p_user_id);

  SELECT * INTO v_profile
  FROM public.user_intelligence_profiles
  WHERE user_id = p_user_id;

  v_hour := EXTRACT(HOUR FROM NOW())::INT;

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
      COALESCE(r.rating, 0) AS rating,
      r.image_url,
      COALESCE(r.delivery_fee, 0) AS delivery_fee,
      r.estimated_delivery_time,
      r.is_open,
      -- Distance calculation (Haversine approximation in km)
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
      -- SCORING ENGINE
      (
        -- Base rating score (0-1 normalized)
        (COALESCE(r.rating, 0) / 5.0) * 0.20
        +
        -- Cuisine match score
        CASE WHEN r.cuisine_type IS NOT NULL
             AND v_profile.cuisine_scores ? r.cuisine_type
        THEN (v_profile.cuisine_scores->>r.cuisine_type)::NUMERIC * 0.25
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
        -- Popularity / review count boost
        CASE WHEN COALESCE(r.review_count, 0) > 50 THEN 0.10
             WHEN COALESCE(r.review_count, 0) > 20 THEN 0.07
             ELSE 0.03
        END
        +
        -- Open restaurant boost
        CASE WHEN r.is_open THEN 0.05 ELSE -0.20 END
      ) AS final_score,
      -- Section assignment
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
      -- Reason text
      CASE
        WHEN r.cuisine_type IS NOT NULL
             AND r.cuisine_type = v_top_cuisine
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

-- ====================================================================
-- 8. RPC: Generate targeted coupon for at-risk users
-- ====================================================================
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
    RETURN jsonb_build_object('generated', FALSE, 'reason', 'active_coupon_exists');
  END IF;

  -- Determine discount based on segment and churn risk
  IF v_profile.user_segment = 'new_user' THEN
    v_discount := 25;
    v_reason := 'Welcome! Enjoy your first order discount';
  ELSIF v_profile.churn_risk > 0.8 THEN
    v_discount := 35;
    v_reason := 'We miss you! Here''s a special deal';
  ELSIF v_profile.churn_risk > 0.6 THEN
    v_discount := 20;
    v_reason := 'It''s been a while — treat yourself!';
  ELSIF v_profile.user_segment = 'power_user' THEN
    v_discount := 10;
    v_reason := 'Thanks for being a loyal customer!';
  ELSE
    v_discount := 15;
    v_reason := 'A little treat just for you';
  END IF;

  -- Generate unique code
  v_code := 'SMART' || UPPER(SUBSTR(gen_random_uuid()::TEXT, 1, 6));

  INSERT INTO public.user_coupons (
    user_id, code, discount_percent, min_order, reason, expires_at
  ) VALUES (
    p_user_id, v_code, v_discount, 200, v_reason,
    NOW() + INTERVAL '3 days'
  ) RETURNING id INTO v_coupon_id;

  RETURN jsonb_build_object(
    'generated', TRUE,
    'coupon_id', v_coupon_id,
    'code', v_code,
    'discount_percent', v_discount,
    'reason', v_reason,
    'expires_in_hours', 72
  );
END;
$$;

-- ====================================================================
-- 9. RPC: Track event (lightweight, called from Flutter)
-- ====================================================================
CREATE OR REPLACE FUNCTION public.track_user_event(
  p_user_id UUID,
  p_event_type TEXT,
  p_metadata JSONB DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_event_id UUID;
BEGIN
  INSERT INTO public.user_events (user_id, event_type, metadata)
  VALUES (p_user_id, p_event_type, p_metadata)
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$$;

-- ====================================================================
-- 10. Cleanup: auto-expire old recommendations & coupons
-- ====================================================================
CREATE OR REPLACE FUNCTION public.cleanup_expired_recommendations()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  DELETE FROM public.ai_recommendations WHERE expires_at < NOW();
  DELETE FROM public.user_coupons WHERE expires_at < NOW() AND is_used = FALSE;
  DELETE FROM public.user_events WHERE created_at < NOW() - INTERVAL '90 days';
END;
$$;
