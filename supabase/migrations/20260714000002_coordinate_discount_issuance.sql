-- ─────────────────────────────────────────────────────────────────────────────
-- Coordinate the two independent discount-issuing mechanisms so the same
-- customer can't receive two overlapping "come back" offers at once.
--
-- Before this migration:
--   - Brain Engine's generate_targeted_coupon(p_user_id) — called client-side
--     whenever a user opens the app (brainEngineProvider) — mints a
--     user_coupons + promo_codes row redeemable by code at checkout.
--   - Decision Engine's generate_promotions() — run nightly by the
--     decision_engine_daily cron — assigns a user_promotions row (surfaced
--     by the "AI Promo" banner in checkout_screen.dart, applied via a tap,
--     no code involved).
--   Each only checked for a pre-existing offer within its OWN table
--   (generate_targeted_coupon looked only at user_coupons; generate_promotions
--   looked only at user_promotions), so a single at-risk/inactive customer
--   could accumulate one of each — two different "here's a discount to come
--   back" offers live in checkout simultaneously, from two different systems.
--
-- Fix: each system now also checks the OTHER system's table before issuing.
-- Whichever offer already exists and is still active wins; nothing is
-- revoked, no schema changes, no Flutter changes (recommendation_service.dart
-- already treats `generated: false` as "no coupon today" and ignores it).
-- ─────────────────────────────────────────────────────────────────────────────

-- 1. generate_targeted_coupon: don't mint a new Brain Engine coupon if the
--    user already has an active, unused Decision Engine promotion waiting.
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
  v_expires_at TIMESTAMPTZ;
  v_existing RECORD;
  v_decision_promo RECORD;
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

  -- Check for existing active coupon
  SELECT * INTO v_existing
  FROM public.user_coupons
  WHERE user_id = p_user_id
    AND is_used = FALSE
    AND expires_at > NOW()
  ORDER BY created_at DESC
  LIMIT 1;

  -- If user is NO LONGER new_user but still has a welcome coupon, expire it
  IF v_existing IS NOT NULL
     AND v_profile.user_segment != 'new_user'
     AND v_existing.reason ILIKE '%first order%' THEN
    -- Mark the welcome coupon as used
    UPDATE public.user_coupons SET is_used = TRUE WHERE id = v_existing.id;
    UPDATE public.promo_codes SET is_active = FALSE WHERE code = v_existing.code;
    v_existing := NULL; -- Force new coupon generation
  END IF;

  -- Return existing valid coupon if still appropriate
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object(
      'generated', TRUE,
      'coupon_id', v_existing.id,
      'code', v_existing.code,
      'discount_percent', v_existing.discount_percent::INT,
      'reason', v_existing.reason,
      'min_order', v_existing.min_order,
      'expires_in_hours', GREATEST(1, EXTRACT(EPOCH FROM v_existing.expires_at - NOW())::INT / 3600)
    );
  END IF;

  -- Cross-system check: Decision Engine may already have an active offer
  -- waiting for this user (surfaced by the checkout "AI Promo" banner).
  -- Don't stack a second independently-generated coupon on top of it.
  SELECT up.* INTO v_decision_promo
  FROM public.user_promotions up
  JOIN public.promotions p ON p.id = up.promotion_id
  WHERE up.user_id = p_user_id
    AND up.used = FALSE
    AND p.active = TRUE
  ORDER BY up.sent_at DESC
  LIMIT 1;

  IF v_decision_promo IS NOT NULL THEN
    RETURN jsonb_build_object(
      'generated', FALSE,
      'reason', 'existing_decision_engine_offer',
      'message', 'You already have an active offer waiting for you at checkout.'
    );
  END IF;

  -- Determine discount based on segment and churn risk
  IF v_profile.user_segment = 'new_user' THEN
    v_discount := 30;
    v_reason := 'Welcome to MealHub! Save 30% on your first order';
    v_min_order := 0;
  ELSIF v_profile.user_segment = 'casual' AND v_profile.total_orders <= 3 THEN
    v_discount := 15;
    v_reason := 'Thanks for ordering! Here''s 15% off your next meal';
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
  ELSIF v_profile.user_segment = 'regular' THEN
    v_discount := 12;
    v_reason := 'You''re on a roll! Enjoy 12% off';
    v_min_order := 100;
  ELSE
    v_discount := 15;
    v_reason := 'A little treat just for you';
    v_min_order := 200;
  END IF;

  -- Generate unique code
  v_code := 'MEAL' || UPPER(SUBSTR(gen_random_uuid()::TEXT, 1, 6));
  v_expires_at := NOW() + INTERVAL '7 days';

  -- Insert into user_coupons (AI tracking table)
  INSERT INTO public.user_coupons (
    user_id, code, discount_percent, min_order, reason, expires_at
  ) VALUES (
    p_user_id, v_code, v_discount, v_min_order, v_reason, v_expires_at
  ) RETURNING id INTO v_coupon_id;

  -- Also insert into promo_codes so checkout validation works
  INSERT INTO public.promo_codes (
    code, description, discount_type, discount_value,
    min_order_amount, max_uses, usage_count, is_active, expires_at
  ) VALUES (
    v_code, v_reason, 'percentage', v_discount,
    v_min_order, 1, 0, TRUE, v_expires_at
  )
  ON CONFLICT (code) DO NOTHING;

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

-- 2. generate_promotions: don't assign a Decision Engine promotion to a user
--    who already has an active, unused Brain Engine coupon.
CREATE OR REPLACE FUNCTION public.generate_promotions()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_at_risk_promo   UUID;
  v_new_promo       UUID;
  v_loyal_promo     UUID;
BEGIN
  SELECT id INTO v_at_risk_promo
  FROM public.promotions
  WHERE target_segment = 'at_risk' AND active = true
  ORDER BY created_at DESC LIMIT 1;

  SELECT id INTO v_new_promo
  FROM public.promotions
  WHERE target_segment = 'new' AND active = true
  ORDER BY created_at DESC LIMIT 1;

  SELECT id INTO v_loyal_promo
  FROM public.promotions
  WHERE target_segment = 'loyal' AND active = true
  ORDER BY created_at DESC LIMIT 1;

  -- At-risk → comeback offer
  IF v_at_risk_promo IS NOT NULL THEN
    INSERT INTO public.user_promotions (user_id, promotion_id)
    SELECT m.user_id, v_at_risk_promo
    FROM public.user_metrics m
    WHERE m.segment = 'at_risk'
      AND NOT EXISTS (
        SELECT 1 FROM public.user_promotions up
        WHERE up.user_id = m.user_id
          AND up.promotion_id = v_at_risk_promo
          AND up.used = false
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.user_coupons uc
        WHERE uc.user_id = m.user_id
          AND uc.is_used = false
          AND uc.expires_at > now()
      )
    ON CONFLICT DO NOTHING;
  END IF;

  -- New → first order incentive
  IF v_new_promo IS NOT NULL THEN
    INSERT INTO public.user_promotions (user_id, promotion_id)
    SELECT m.user_id, v_new_promo
    FROM public.user_metrics m
    WHERE m.segment = 'new'
      AND NOT EXISTS (
        SELECT 1 FROM public.user_promotions up
        WHERE up.user_id = m.user_id
          AND up.promotion_id = v_new_promo
          AND up.used = false
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.user_coupons uc
        WHERE uc.user_id = m.user_id
          AND uc.is_used = false
          AND uc.expires_at > now()
      )
    ON CONFLICT DO NOTHING;
  END IF;

  -- Loyal → upsell (no heavy discounts)
  IF v_loyal_promo IS NOT NULL THEN
    INSERT INTO public.user_promotions (user_id, promotion_id)
    SELECT m.user_id, v_loyal_promo
    FROM public.user_metrics m
    WHERE m.segment = 'loyal'
      AND NOT EXISTS (
        SELECT 1 FROM public.user_promotions up
        WHERE up.user_id = m.user_id
          AND up.promotion_id = v_loyal_promo
          AND up.used = false
      )
      AND NOT EXISTS (
        SELECT 1 FROM public.user_coupons uc
        WHERE uc.user_id = m.user_id
          AND uc.is_used = false
          AND uc.expires_at > now()
      )
    ON CONFLICT DO NOTHING;
  END IF;

  -- Update promotion_results sent counts
  INSERT INTO public.promotion_results (promotion_id, sent, used, revenue_generated)
  SELECT
    up.promotion_id,
    COUNT(*)                                                  AS sent,
    COUNT(*) FILTER (WHERE up.used = true)                   AS used,
    COALESCE(SUM(o.total_amount) FILTER (WHERE up.used=true), 0) AS revenue_generated
  FROM public.user_promotions up
  LEFT JOIN public.orders o
    ON o.user_id = up.user_id
   AND o.created_at  >= up.sent_at
  GROUP BY up.promotion_id
  ON CONFLICT (promotion_id) DO UPDATE
    SET sent               = EXCLUDED.sent,
        used               = EXCLUDED.used,
        revenue_generated  = EXCLUDED.revenue_generated,
        updated_at         = now();
END;
$$;
