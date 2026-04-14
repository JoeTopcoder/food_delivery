-- ====================================================================
-- 053: Bridge AI coupons to promo_codes table
-- When generate_targeted_coupon creates a coupon, also insert into
-- promo_codes so checkout validation works seamlessly.
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
  v_min_order DOUBLE PRECISION;
  v_expires_at TIMESTAMPTZ;
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

  -- Don't generate if user already has an active coupon — return existing one
  IF EXISTS (
    SELECT 1 FROM public.user_coupons
    WHERE user_id = p_user_id
      AND is_used = FALSE
      AND expires_at > NOW()
  ) THEN
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
