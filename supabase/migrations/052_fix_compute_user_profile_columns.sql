-- ====================================================================
-- 052: Fix compute_user_profile column names
-- completed_at → delivered_at, discount → discount_amount
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
$$;
