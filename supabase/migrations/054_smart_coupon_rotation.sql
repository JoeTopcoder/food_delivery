-- ====================================================================
-- 054: Smart coupon rotation after first order
-- Replace stale welcome coupon when user is no longer new_user.
-- Also mark AI coupon as used in user_coupons + promo_codes after order.
-- ====================================================================

-- 1. Updated generate_targeted_coupon: expire welcome coupon if user graduated
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

-- 2. Trigger to mark AI coupon used when promo_codes usage increments
CREATE OR REPLACE FUNCTION public.sync_ai_coupon_usage()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.usage_count > OLD.usage_count AND NEW.code LIKE 'MEAL%' THEN
    UPDATE public.user_coupons
    SET is_used = TRUE
    WHERE code = NEW.code AND is_used = FALSE;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_ai_coupon_usage ON public.promo_codes;
CREATE TRIGGER trg_sync_ai_coupon_usage
  AFTER UPDATE OF usage_count ON public.promo_codes
  FOR EACH ROW
  EXECUTE FUNCTION public.sync_ai_coupon_usage();
