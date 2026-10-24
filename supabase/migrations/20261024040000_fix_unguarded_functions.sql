-- ============================================================================
-- Fix the 20 unguarded privileged SECDEF functions (IDOR / caller-supplied id).
--   * User-id functions: pin p_user_id to auth.uid() for JWT callers; service-
--     role/edge callers (auth.uid() NULL) keep the passed id. (CLAUDE.md pattern)
--   * Driver-id functions: require the caller to own the driver (or be admin, or
--     service-role) rather than trusting the passed driver_id.
--   * ensure_user_profile: pin id to auth.uid() and clamp role (never admin) for
--     JWT callers.
--   * resolve_driver_user_id / log_driver_verification: internal only (no app/edge
--     caller) -> restrict to service_role.
-- Bodies are otherwise unchanged. Verified against which functions the Dart app
-- calls (all pinned ones ARE app-called, so locking would have broken them).
-- ============================================================================

CREATE OR REPLACE FUNCTION public.calculate_membership_discount(p_user_id uuid, p_business_id uuid, p_subtotal numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  d record;
  v_amount numeric := 0;
  v_used_total int;
  v_used_customer int;
  v_biz_pct numeric;
BEGIN
  p_user_id := COALESCE(auth.uid(), p_user_id);  -- pin to caller (IDOR fix)
  -- Non-members get nothing.
  IF NOT public.is_hotbite_plus_member(p_user_id) THEN
    RETURN jsonb_build_object('discount_amount', 0);
  END IF;

  -- Pick the deal that yields the largest valid discount for this business.
  FOR d IN
    SELECT * FROM public.membership_deals md
    WHERE md.business_id = p_business_id
      AND md.status = 'approved'
      AND md.is_active = true
      AND md.requires_membership = true
      AND (md.start_date IS NULL OR md.start_date <= now())
      AND (md.end_date IS NULL OR md.end_date >= now())
      AND p_subtotal >= COALESCE(md.minimum_order_amount, 0)
      AND md.discount_type IN ('percentage','fixed_amount','special_price')
  LOOP
    -- Usage limits.
    SELECT count(*) INTO v_used_total
      FROM public.order_membership_discounts WHERE deal_id = d.id;
    IF d.usage_limit IS NOT NULL AND v_used_total >= d.usage_limit THEN
      CONTINUE;
    END IF;
    SELECT count(*) INTO v_used_customer
      FROM public.order_membership_discounts omd
      JOIN public.orders o ON o.id = omd.order_id
      WHERE omd.deal_id = d.id AND o.user_id = p_user_id;
    IF COALESCE(d.usage_limit_per_customer, 1) IS NOT NULL
       AND v_used_customer >= COALESCE(d.usage_limit_per_customer, 1) THEN
      CONTINUE;
    END IF;

    -- Discount by type.
    DECLARE v_this numeric := 0;
    BEGIN
      IF d.discount_type = 'percentage' THEN
        v_this := p_subtotal * (d.discount_value / 100.0);
      ELSIF d.discount_type = 'fixed_amount' THEN
        v_this := d.discount_value;
      ELSIF d.discount_type = 'special_price' THEN
        v_this := GREATEST(0, p_subtotal - d.discount_value);
      END IF;
      IF d.maximum_discount_amount IS NOT NULL THEN
        v_this := LEAST(v_this, d.maximum_discount_amount);
      END IF;
      v_this := LEAST(v_this, p_subtotal);   -- never exceed the subtotal
      IF v_this > v_amount THEN
        v_amount := v_this;
        v_biz_pct := COALESCE(d.business_funded_pct, 100);
        -- stash the winning deal id via a temp on the record
        PERFORM set_config('hotbite.deal_id', d.id::text, true);
        PERFORM set_config('hotbite.deal_type', d.discount_type, true);
      END IF;
    END;
  END LOOP;

  IF v_amount <= 0 THEN
    RETURN jsonb_build_object('discount_amount', 0);
  END IF;

  v_amount := round(v_amount, 2);
  RETURN jsonb_build_object(
    'discount_amount', v_amount,
    'deal_id', current_setting('hotbite.deal_id', true),
    'discount_type', current_setting('hotbite.deal_type', true),
    'business_funded_amount', round(v_amount * v_biz_pct / 100.0, 2),
    'hotbite_funded_amount', round(v_amount * (100 - v_biz_pct) / 100.0, 2)
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.generate_targeted_coupon(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_profile     RECORD;
  v_code        TEXT;
  v_discount    INT;
  v_reason      TEXT;
  v_coupon_id   UUID;
  v_min_order   DOUBLE PRECISION;
  v_expires_at  TIMESTAMPTZ;
  v_existing    RECORD;
  v_is_welcome  BOOLEAN;
BEGIN
  p_user_id := COALESCE(auth.uid(), p_user_id);  -- pin to caller (IDOR fix)
  SELECT * INTO v_profile
  FROM public.user_intelligence_profiles WHERE user_id = p_user_id;

  IF v_profile IS NULL THEN
    PERFORM public.compute_user_profile(p_user_id);
    SELECT * INTO v_profile
    FROM public.user_intelligence_profiles WHERE user_id = p_user_id;
  END IF;

  -- Hand back a coupon they can still use rather than minting another.
  SELECT * INTO v_existing
  FROM public.user_coupons
  WHERE user_id = p_user_id AND is_used = FALSE AND expires_at > NOW()
  ORDER BY created_at DESC
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object(
      'generated', FALSE,
      'reason_code', 'existing_active_coupon',
      'coupon_id', v_existing.id,
      'code', v_existing.code,
      'discount_percent', v_existing.discount_percent::INT,
      'reason', v_existing.reason,
      'min_order', v_existing.min_order
    );
  END IF;

  v_is_welcome := (v_profile.user_segment = 'new_user');

  -- A first-order offer is once in a customer's life, expired or not.
  IF v_is_welcome AND EXISTS (
    SELECT 1 FROM public.user_coupons
    WHERE user_id = p_user_id AND reason ILIKE '%first order%'
  ) THEN
    RETURN jsonb_build_object(
      'generated', FALSE,
      'reason_code', 'welcome_already_issued'
    );
  END IF;

  -- Everything else: at most one new coupon a week, whatever calls this.
  IF NOT v_is_welcome AND EXISTS (
    SELECT 1 FROM public.user_coupons
    WHERE user_id = p_user_id AND created_at > NOW() - INTERVAL '7 days'
  ) THEN
    RETURN jsonb_build_object(
      'generated', FALSE,
      'reason_code', 'issued_recently'
    );
  END IF;

  IF v_is_welcome THEN
    v_discount := 30; v_min_order := 0;
    v_reason := 'Welcome to HotBite! Save 30% on your first order';
  ELSIF v_profile.churn_risk > 0.8 THEN
    v_discount := 35; v_min_order := 200;
    v_reason := 'We miss you! Here''s a special deal';
  ELSIF v_profile.churn_risk > 0.6 THEN
    v_discount := 20; v_min_order := 150;
    v_reason := 'It''s been a while - treat yourself!';
  ELSIF v_profile.user_segment = 'power_user' THEN
    v_discount := 10; v_min_order := 300;
    v_reason := 'Thanks for being a loyal customer!';
  ELSE
    v_discount := 15; v_min_order := 200;
    v_reason := 'A little treat just for you';
  END IF;

  v_code := 'MEAL' || UPPER(SUBSTR(gen_random_uuid()::TEXT, 1, 6));
  v_expires_at := NOW() + INTERVAL '7 days';

  INSERT INTO public.user_coupons
    (user_id, code, discount_percent, reason, min_order, expires_at, is_used)
  VALUES
    (p_user_id, v_code, v_discount, v_reason, v_min_order, v_expires_at, FALSE)
  RETURNING id INTO v_coupon_id;

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
$function$;

CREATE OR REPLACE FUNCTION public.process_volume_bonus(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_account       earning_accounts;
  v_month_key     TEXT := to_char(now(), 'YYYY-MM');
  v_bonus_300     DECIMAL;
  v_bonus_1000    DECIMAL;
  v_bonus_3000    DECIMAL;
  v_awarded       DECIMAL := 0;
  v_already       BOOLEAN;
BEGIN
  p_user_id := COALESCE(auth.uid(), p_user_id);  -- pin to caller (IDOR fix)
  SELECT * INTO v_account
  FROM earning_accounts WHERE user_id = p_user_id;

  IF v_account IS NULL OR v_account.tier != 'leader' THEN
    RETURN jsonb_build_object('awarded', 0, 'reason', 'not_leader');
  END IF;

  -- Ensure month_key is current
  IF v_account.month_key != v_month_key THEN
    UPDATE earning_accounts SET
      monthly_orders = 0, monthly_earned = 0, month_key = v_month_key
    WHERE user_id = p_user_id;
    v_account.monthly_orders := 0;
  END IF;

  -- Get bonus thresholds
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_volume_bonus_300'), 25.00)
    INTO v_bonus_300;
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_volume_bonus_1000'), 100.00)
    INTO v_bonus_1000;
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_volume_bonus_3000'), 250.00)
    INTO v_bonus_3000;

  -- Check if 3000 milestone already awarded this month
  IF v_account.monthly_orders >= 3000 THEN
    SELECT EXISTS (
      SELECT 1 FROM earning_transactions
      WHERE user_id = p_user_id AND type = 'volume_bonus'
        AND description LIKE '%3000%'
        AND created_at >= date_trunc('month', now())
    ) INTO v_already;
    IF NOT v_already THEN
      PERFORM credit_earning(p_user_id, v_bonus_3000, 'volume_bonus', NULL, NULL,
        'Volume bonus: 3000 monthly orders');
      v_awarded := v_awarded + v_bonus_3000;
    END IF;
  ELSIF v_account.monthly_orders >= 1000 THEN
    SELECT EXISTS (
      SELECT 1 FROM earning_transactions
      WHERE user_id = p_user_id AND type = 'volume_bonus'
        AND description LIKE '%1000%'
        AND created_at >= date_trunc('month', now())
    ) INTO v_already;
    IF NOT v_already THEN
      PERFORM credit_earning(p_user_id, v_bonus_1000, 'volume_bonus', NULL, NULL,
        'Volume bonus: 1000 monthly orders');
      v_awarded := v_awarded + v_bonus_1000;
    END IF;
  ELSIF v_account.monthly_orders >= 300 THEN
    SELECT EXISTS (
      SELECT 1 FROM earning_transactions
      WHERE user_id = p_user_id AND type = 'volume_bonus'
        AND description LIKE '%300 monthly%'
        AND created_at >= date_trunc('month', now())
    ) INTO v_already;
    IF NOT v_already THEN
      PERFORM credit_earning(p_user_id, v_bonus_300, 'volume_bonus', NULL, NULL,
        'Volume bonus: 300 monthly orders');
      v_awarded := v_awarded + v_bonus_300;
    END IF;
  END IF;

  RETURN jsonb_build_object('awarded', v_awarded, 'monthly_orders', v_account.monthly_orders);
END;
$function$;

CREATE OR REPLACE FUNCTION public.track_user_event(p_user_id uuid, p_event_type text, p_metadata jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_event_id UUID;
BEGIN
  p_user_id := COALESCE(auth.uid(), p_user_id);  -- pin to caller (IDOR fix)
  INSERT INTO public.user_events (user_id, event_type, metadata)
  VALUES (p_user_id, p_event_type, p_metadata)
  RETURNING id INTO v_event_id;

  RETURN v_event_id;
END;
$function$;

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
      AND r.store_type IN ('grocery', 'both')
  )
  SELECT * FROM scored
  ORDER BY scored.final_score DESC
  LIMIT p_limit;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_cart_recommendations(p_user_id uuid, p_cart_restaurant_ids uuid[], p_delivery_lat double precision DEFAULT NULL::double precision, p_delivery_lng double precision DEFAULT NULL::double precision, p_max_distance_km double precision DEFAULT 15.0, p_limit integer DEFAULT 3)
 RETURNS TABLE(restaurant_id uuid, restaurant_name text, cuisine_type text, rating numeric, image_url text, estimated_delivery_time integer, distance_km double precision, delivery_fee numeric, behavior_score double precision, final_score double precision, reason text, is_co_order boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_cart_names TEXT;
BEGIN
  p_user_id := COALESCE(auth.uid(), p_user_id);  -- pin to caller (IDOR fix)

  -- Build a comma-separated list of current cart restaurant names (for reason strings)
  SELECT string_agg(name, ' & ' ORDER BY name)
  INTO   v_cart_names
  FROM   restaurants
  WHERE  id = ANY(p_cart_restaurant_ids);

  RETURN QUERY
  WITH

  -- â”€â”€ 1. Co-order signal: restaurants ordered together with cart restaurants â”€â”€
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

  -- â”€â”€ 2. General affinity: all restaurants the user has ever ordered from â”€â”€
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

  -- â”€â”€ 3. Combined behaviour score â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
  behaviour AS (
    SELECT
      COALESCE(co.restaurant_id, af.restaurant_id) AS restaurant_id,
      COALESCE(co.score, 0) + COALESCE(af.score, 0)  AS behavior_score,
      COALESCE(co.score, 0) >= 3                       AS is_co_order
    FROM      co_order_scores co
    FULL JOIN affinity_scores  af ON af.restaurant_id = co.restaurant_id
  ),

  -- â”€â”€ 4. Join with restaurant metadata + distance scoring â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
$function$;

CREATE OR REPLACE FUNCTION public.get_recommendations(p_user_id uuid, p_limit integer DEFAULT 20)
 RETURNS TABLE(item_id uuid, item_name text, item_price numeric, item_image_url text, restaurant_id uuid, restaurant_name text, restaurant_image text, score real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  p_user_id := COALESCE(auth.uid(), p_user_id);  -- pin to caller (IDOR fix)
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
    m.price::numeric AS item_price,
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
$function$;

CREATE OR REPLACE FUNCTION public.compute_user_profile(p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
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
  p_user_id := COALESCE(auth.uid(), p_user_id);  -- pin to caller (IDOR fix)
  -- Total completed orders
  SELECT COUNT(*) INTO v_total_orders
  FROM public.orders
  WHERE user_id = p_user_id AND status = 'delivered';

  -- Days since last order (use delivered_at, fall back to ordered_at)
  SELECT COALESCE(
    EXTRACT(DAY FROM NOW() - MAX(COALESCE(delivered_at, ordered_at)))::INT, 999
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
      AND COALESCE(o.delivered_at, o.ordered_at) > NOW() - INTERVAL '90 days'
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
    ROUND(COUNT(*) FILTER (WHERE discount_amount > 0)::NUMERIC / GREATEST(COUNT(*), 1), 2),
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
$function$;

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
  p_user_id := COALESCE(auth.uid(), p_user_id);  -- pin to caller (IDOR fix)
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

CREATE OR REPLACE FUNCTION public.get_customer_habits(p_user_id uuid, p_store_type text DEFAULT 'food'::text, p_limit integer DEFAULT 12)
 RETURNS TABLE(menu_item_id uuid, item_name text, restaurant_id uuid, store_name text, price double precision, times_ordered bigint, last_ordered timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH store_scope AS (
    SELECT id FROM public.restaurants
    WHERE is_verified
      AND store_type = ANY (
        CASE WHEN p_store_type = 'grocery'
             THEN ARRAY['grocery','both'] ELSE ARRAY['food','both'] END
      )
  ),
  purchased AS (
    -- Real money changed hands: weight 2.
    SELECT oi.menu_item_id, 2::BIGINT AS weight, o.created_at
    FROM public.order_items oi
    JOIN public.orders o ON o.id = oi.order_id
    WHERE o.user_id = COALESCE(auth.uid(), p_user_id)
      AND oi.menu_item_id IS NOT NULL
      AND o.restaurant_id IN (SELECT id FROM store_scope)
  ),
  accepted AS (
    -- Accepted a concierge basket: weight 1.
    SELECT (li->>'item_id')::UUID AS menu_item_id, 1::BIGINT AS weight, d.created_at
    FROM public.concierge_cart_drafts d
    JOIN LATERAL jsonb_array_elements(d.line_items) li ON true
    WHERE d.user_id = COALESCE(auth.uid(), p_user_id)
      AND d.status = 'consumed'
      AND d.restaurant_id IN (SELECT id FROM store_scope)
      AND (li->>'item_id') ~ '^[0-9a-f-]{36}$'
  ),
  combined AS (
    SELECT * FROM purchased UNION ALL SELECT * FROM accepted
  )
  SELECT m.id, m.name, m.restaurant_id, r.name, m.price,
         SUM(c.weight) AS times_ordered,
         MAX(c.created_at) AS last_ordered
  FROM combined c
  JOIN public.menus m ON m.id = c.menu_item_id
  JOIN public.restaurants r ON r.id = m.restaurant_id
  WHERE m.is_available
  GROUP BY m.id, m.name, m.restaurant_id, r.name, m.price
  ORDER BY SUM(c.weight) DESC, MAX(c.created_at) DESC
  LIMIT p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.get_usual_order_items(p_user_id uuid, p_restaurant_id uuid DEFAULT NULL::uuid, p_day_of_week integer DEFAULT NULL::integer, p_limit integer DEFAULT 5)
 RETURNS TABLE(menu_item_id uuid, item_name text, restaurant_id uuid, restaurant_name text, order_count bigint, avg_price numeric, last_ordered_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    oi.menu_item_id,
    oi.item_name,
    o.restaurant_id,
    r.name,
    COUNT(*) AS order_count,
    AVG(oi.price) AS avg_price,
    MAX(o.ordered_at) AS last_ordered_at
  FROM order_items oi
  JOIN orders o ON o.id = oi.order_id
  JOIN restaurants r ON r.id = o.restaurant_id
  WHERE o.user_id = COALESCE(auth.uid(), p_user_id)
    AND o.status <> 'cancelled'
    AND (p_restaurant_id IS NULL OR o.restaurant_id = p_restaurant_id)
    AND (p_day_of_week IS NULL OR EXTRACT(DOW FROM o.ordered_at) = p_day_of_week)
  GROUP BY oi.menu_item_id, oi.item_name, o.restaurant_id, r.name
  ORDER BY order_count DESC, last_ordered_at DESC
  LIMIT p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.get_recent_hotel_searches(p_user_id uuid, p_limit integer DEFAULT 5)
 RETURNS TABLE(destination text, destination_code text, check_in date, check_out date, rooms integer, adults integer, children integer, searched_at timestamp with time zone)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
  SELECT DISTINCT ON (destination_code)
    destination, destination_code, check_in, check_out, rooms, adults, children, created_at
  FROM public.hotel_search_logs
  WHERE user_id = COALESCE(auth.uid(), p_user_id)
    AND destination_code IS NOT NULL
  ORDER BY destination_code, created_at DESC
  LIMIT p_limit;
$function$;

CREATE OR REPLACE FUNCTION public.process_signup_referral_bonus(p_referred_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_referrer_id       UUID;
  v_referrer_bonus    DECIMAL;
  v_referred_bonus    DECIMAL;
  v_already_rewarded  BOOLEAN;
BEGIN
  p_referred_user_id := COALESCE(auth.uid(), p_referred_user_id);  -- pin to caller
  -- Find referrer
  SELECT referred_by INTO v_referrer_id
  FROM users WHERE id = p_referred_user_id;

  IF v_referrer_id IS NULL THEN
    RETURN jsonb_build_object('credited', false, 'reason', 'no_referrer');
  END IF;

  -- Check if already rewarded
  SELECT reward_given INTO v_already_rewarded
  FROM referrals
  WHERE referrer_id = v_referrer_id AND referred_id = p_referred_user_id
  LIMIT 1;

  IF v_already_rewarded IS TRUE THEN
    RETURN jsonb_build_object('credited', false, 'reason', 'already_rewarded');
  END IF;

  -- Get bonus amounts from config
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_referrer_signup_bonus'), 2.00)
    INTO v_referrer_bonus;
  SELECT COALESCE((SELECT value::decimal FROM app_config WHERE key = 'earning_referred_first_order'), 3.00)
    INTO v_referred_bonus;

  -- Credit referrer $2
  BEGIN
    PERFORM credit_earning(
      v_referrer_id,
      v_referrer_bonus,
      'signup_bonus',
      p_referred_user_id,
      NULL,
      'Signup bonus: friend completed first order'
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Credit referred user $3
  BEGIN
    PERFORM credit_earning(
      p_referred_user_id,
      v_referred_bonus,
      'referred_first_order',
      v_referrer_id,
      NULL,
      'Welcome bonus: first order discount'
    );
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Mark referral as rewarded
  UPDATE referrals SET reward_given = true
  WHERE referrer_id = v_referrer_id AND referred_id = p_referred_user_id;

  -- Update referrer's direct ref count
  UPDATE earning_accounts SET
    total_direct_refs = total_direct_refs + 1,
    updated_at = now()
  WHERE user_id = v_referrer_id;

  PERFORM update_earning_tier(v_referrer_id);

  RETURN jsonb_build_object(
    'credited', true,
    'referrer_bonus', v_referrer_bonus,
    'referred_bonus', v_referred_bonus
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.ensure_user_profile(p_user_id uuid, p_email text, p_name text, p_role text DEFAULT 'user'::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF auth.uid() IS NOT NULL THEN p_user_id := auth.uid(); IF p_role IS NULL OR p_role NOT IN ('user','customer','driver','restaurant','provider') THEN p_role := 'user'; END IF; END IF;
  INSERT INTO public.users (id, email, name, role, is_active, created_at)
  VALUES (p_user_id, p_email, COALESCE(NULLIF(p_name, ''), 'User'), p_role, TRUE, NOW())
  ON CONFLICT (id) DO NOTHING;
END;
$function$;

CREATE OR REPLACE FUNCTION public.calculate_driver_score(p_driver_id uuid)
 RETURNS TABLE(score double precision, tier text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_acceptance DOUBLE PRECISION;
  v_completion DOUBLE PRECISION;
  v_ontime DOUBLE PRECISION;
  v_rating DOUBLE PRECISION;
  v_score DOUBLE PRECISION;
  v_tier TEXT;
  v_silver DOUBLE PRECISION;
  v_gold DOUBLE PRECISION;
  v_elite DOUBLE PRECISION;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() AND NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.id = p_driver_id AND d.user_id = auth.uid()) THEN RAISE EXCEPTION 'Not authorized for this driver'; END IF;
  SELECT ds.acceptance_rate, ds.completion_rate, ds.on_time_rate, ds.avg_customer_rating
  INTO v_acceptance, v_completion, v_ontime, v_rating
  FROM public.driver_stats ds WHERE ds.driver_id = p_driver_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 50.0::DOUBLE PRECISION, 'bronze'::TEXT;
    RETURN;
  END IF;

  -- Weighted score: completion 30%, on_time 25%, rating 25%, acceptance 20%
  v_score := (COALESCE(v_completion, 0) * 0.30 +
              COALESCE(v_ontime, 0) * 0.25 +
              COALESCE(v_rating, 0) / 5.0 * 100 * 0.25 +
              COALESCE(v_acceptance, 0) * 0.20);
  v_score := GREATEST(0, LEAST(100, v_score));

  -- Get tier thresholds from config
  SELECT COALESCE((SELECT c.value::DOUBLE PRECISION FROM public.app_config c WHERE c.key = 'driver_tier_silver_score'), 60) INTO v_silver;
  SELECT COALESCE((SELECT c.value::DOUBLE PRECISION FROM public.app_config c WHERE c.key = 'driver_tier_gold_score'), 75) INTO v_gold;
  SELECT COALESCE((SELECT c.value::DOUBLE PRECISION FROM public.app_config c WHERE c.key = 'driver_tier_elite_score'), 90) INTO v_elite;

  IF v_score >= v_elite THEN v_tier := 'elite';
  ELSIF v_score >= v_gold THEN v_tier := 'gold';
  ELSIF v_score >= v_silver THEN v_tier := 'silver';
  ELSE v_tier := 'bronze';
  END IF;

  -- Update driver
  UPDATE public.drivers SET driver_score = v_score, tier = v_tier WHERE id = p_driver_id;
  UPDATE public.driver_stats SET driver_score = v_score, tier = v_tier, tier_updated_at = NOW(), updated_at = NOW() WHERE driver_stats.driver_id = p_driver_id;

  RETURN QUERY SELECT v_score, v_tier;
END;
$function$;

CREATE OR REPLACE FUNCTION public.compute_driver_priority(p_driver_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  cfg record; d record;
  w jsonb; win_days int; min_prov int; min_dev int;
  f_rating numeric; f_ontime numeric; f_completion numeric;
  f_accept numeric; f_pickup numeric; f_complaints numeric;
  n_completed int; n_cancelled int; n_recent_completed int; n_recent_ontime int;
  score numeric; prev numeric; provisional boolean; standing text; stats jsonb;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() AND NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.id = p_driver_id AND d.user_id = auth.uid()) THEN RAISE EXCEPTION 'Not authorized for this driver'; END IF;
  SELECT * INTO cfg FROM public.driver_priority_config WHERE id = 1;
  SELECT * INTO d FROM public.drivers WHERE id = p_driver_id;
  IF d.id IS NULL THEN RETURN NULL; END IF;

  w := cfg.weights;
  win_days := COALESCE((cfg.rolling->>'days')::int, 30);
  min_prov := COALESCE((cfg.min_deliveries->>'provisional')::int, 10);

  -- Recent (rolling-window) delivery counts, computed from raw orders.
  SELECT
    count(*) FILTER (WHERE o.status = 'delivered'),
    count(*) FILTER (WHERE o.status = 'delivered'
        AND o.delivered_at IS NOT NULL AND o.estimated_delivery_at IS NOT NULL
        AND o.delivered_at <= o.estimated_delivery_at)
  INTO n_recent_completed, n_recent_ontime
  FROM public.orders o
  WHERE o.driver_id = p_driver_id
    AND o.created_at > now() - make_interval(days => win_days);

  n_completed := COALESCE(d.completed_deliveries, 0);
  n_cancelled := COALESCE(d.cancelled_deliveries, 0);
  provisional := n_completed < min_prov;

  -- Factor scores (0â€“100), all from trusted data.
  f_rating := COALESCE(d.rating,0)/5.0*100;
  -- Prefer recent on-time; fall back to the maintained rate.
  f_ontime := CASE WHEN n_recent_completed > 0
                   THEN n_recent_ontime::numeric/n_recent_completed*100
                   ELSE COALESCE(public._pct(d.on_time_rate), 100) END;
  f_completion := CASE WHEN (n_completed+n_cancelled) > 0
                       THEN n_completed::numeric/(n_completed+n_cancelled)*100
                       ELSE 100 END;
  f_accept := COALESCE(public._pct(d.acceptance_rate), 100);
  f_pickup := f_ontime;                 -- pickup proxy until a pickup metric exists
  f_complaints := 100;                  -- no validated-complaint store yet -> perfect

  score := round(
      (w->>'customer_rating')::numeric * f_rating
    + (w->>'on_time')::numeric        * f_ontime
    + (w->>'completion')::numeric     * f_completion
    + (w->>'acceptance')::numeric     * f_accept
    + (w->>'pickup')::numeric         * f_pickup
    + (w->>'complaints')::numeric     * f_complaints
  , 1);
  score := GREATEST(0, LEAST(100, score));

  standing := public.driver_standing_for_score(score, provisional);
  prev := COALESCE(d.driver_score, 0);

  stats := jsonb_build_object(
    'customer_rating', round(COALESCE(d.rating,0)::numeric,2),
    'on_time', round(f_ontime,0),
    'completion', round(f_completion,0),
    'acceptance', round(f_accept,0),
    'pickup', round(f_pickup,0),
    'complaints', 0,
    'completed_deliveries', n_completed,
    'recent_completed', n_recent_completed
  );

  -- Write under the trusted flag so the protection trigger permits it.
  PERFORM set_config('hotbite.priority_write','on', true);
  UPDATE public.drivers
     SET driver_score = score, tier = standing,
         priority_standing = standing, priority_provisional = provisional,
         priority_stats = stats, priority_updated_at = now()
   WHERE id = p_driver_id;
  PERFORM set_config('hotbite.priority_write','off', true);

  IF round(prev,1) <> round(score,1) THEN
    INSERT INTO public.driver_priority_events
      (driver_id, event_type, score_change, previous_score, new_score, reason, created_by)
    VALUES (p_driver_id, 'recompute', round(score-prev,1), prev, score,
            'Automatic recompute from recent performance', NULL);
  END IF;

  RETURN jsonb_build_object('score',score,'standing',standing,'provisional',provisional,'stats',stats);
END; $function$;

CREATE OR REPLACE FUNCTION public.recompute_driver_acceptance(p_driver_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_accepted integer;
  v_declined integer;
  v_rate     numeric;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() AND NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.id = p_driver_id AND d.user_id = auth.uid()) THEN RAISE EXCEPTION 'Not authorized for this driver'; END IF;
  IF p_driver_id IS NULL THEN
    RETURN NULL;
  END IF;

  SELECT count(*) INTO v_accepted
  FROM orders
  WHERE driver_id = p_driver_id
    AND status = 'delivered'
    AND ordered_at >= now() - interval '30 days';

  SELECT count(*) INTO v_declined
  FROM driver_declined_orders
  WHERE driver_id = p_driver_id
    AND declined_at >= now() - interval '30 days';

  v_rate := CASE
    WHEN (v_accepted + v_declined) > 0
      THEN round((v_accepted::numeric / (v_accepted + v_declined)) * 100, 1)
    ELSE 100
  END;

  INSERT INTO driver_stats (driver_id, orders_accepted, orders_declined,
                            acceptance_rate, updated_at)
  VALUES (p_driver_id, v_accepted, v_declined, v_rate, now())
  ON CONFLICT (driver_id) DO UPDATE SET
    orders_accepted = excluded.orders_accepted,
    orders_declined = excluded.orders_declined,
    acceptance_rate = excluded.acceptance_rate,
    updated_at = now();

  RETURN jsonb_build_object(
    'orders_accepted', v_accepted,
    'orders_declined', v_declined,
    'acceptance_rate', v_rate
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_driver_priority(p_driver_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE res jsonb; t jsonb; standing text; score numeric; provisional boolean;
        next_std text; next_min numeric; gap numeric; stats jsonb; hint text;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() AND NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.id = p_driver_id AND d.user_id = auth.uid()) THEN RAISE EXCEPTION 'Not authorized for this driver'; END IF;
  res := public.compute_driver_priority(p_driver_id);
  IF res IS NULL THEN RETURN NULL; END IF;
  score := (res->>'score')::numeric; standing := res->>'standing';
  provisional := (res->>'provisional')::boolean; stats := res->'stats';
  SELECT thresholds INTO t FROM public.driver_priority_config WHERE id=1;

  -- Determine the next standing up and the points needed.
  next_std := CASE standing
    WHEN 'NEEDS_IMPROVEMENT' THEN 'STANDARD' WHEN 'STANDARD' THEN 'GOOD_STANDING'
    WHEN 'GOOD_STANDING' THEN 'PRIORITY' WHEN 'PRIORITY' THEN 'ELITE' ELSE NULL END;
  IF next_std IS NOT NULL THEN
    next_min := (t->next_std->>0)::numeric; gap := GREATEST(0, next_min - score);
  END IF;

  -- Improvement hint: point at the weakest factor.
  SELECT k INTO hint FROM (
    SELECT 'on-time delivery' k, (stats->>'on_time')::numeric v
    UNION ALL SELECT 'completion rate', (stats->>'completion')::numeric
    UNION ALL SELECT 'acceptance rate', (stats->>'acceptance')::numeric
    UNION ALL SELECT 'customer rating', (stats->>'customer_rating')::numeric*20
  ) s ORDER BY v ASC LIMIT 1;

  RETURN res
    || jsonb_build_object(
        'next_standing', next_std,
        'points_to_next', gap,
        'improve_factor', hint,
        'thresholds', t);
END; $function$;

-- Internal-only: service_role only.
REVOKE ALL ON FUNCTION public.resolve_driver_user_id(p_driver_id uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.log_driver_verification(p_driver_id uuid, p_action text, p_actor_id uuid, p_old_status text, p_new_status text, p_notes text, p_metadata jsonb) FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';
