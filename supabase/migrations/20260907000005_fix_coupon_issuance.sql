-- Migration: stop unbounded coupon issuance, and neutralise the backlog
--
-- generate_targeted_coupon guarded against duplicates by looking for an
-- existing coupon that was unused AND UNEXPIRED. Once a coupon lapsed the guard
-- saw nothing and issued another, so anything calling this on a schedule
-- accumulated coupons indefinitely: 514 across 16 users, none ever redeemed,
-- including 125 identical "Save 30% on your first order" coupons issued to one
-- customer in a single day. Every unexpired one is a live 30% discount.
--
-- Two guards replace it:
--   * A welcome coupon is issued ONCE PER CUSTOMER EVER. "Your first order"
--     means exactly that; expiry does not entitle someone to another.
--   * Any other coupon is rate-limited to one per customer per 7 days, so a
--     scheduled caller cannot mint an unbounded pile.

CREATE OR REPLACE FUNCTION public.generate_targeted_coupon(p_user_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER AS $function$
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
    v_reason := 'Welcome to MealHub! Save 30% on your first order';
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

-- ── Neutralise the backlog ─────────────────────────────────────────────────
-- Marked used rather than deleted: promo_codes rows were bridged from these,
-- and the history is worth keeping. Each customer keeps their single most
-- recent still-valid coupon so nobody loses an entitlement they can see.
WITH keep AS (
  SELECT DISTINCT ON (user_id) id
  FROM public.user_coupons
  WHERE is_used = FALSE AND expires_at > NOW()
  ORDER BY user_id, created_at DESC
)
UPDATE public.user_coupons c
SET    is_used = TRUE
WHERE  c.is_used = FALSE
  AND  c.id NOT IN (SELECT id FROM keep);

-- Deactivate the bridged promo_codes rows for anything just retired, so the
-- codes cannot be redeemed through the manual checkout path either.
UPDATE public.promo_codes p
SET    is_active = FALSE
WHERE  p.is_active
  AND  EXISTS (
    SELECT 1 FROM public.user_coupons c
    WHERE UPPER(c.code) = UPPER(p.code) AND c.is_used
  );

NOTIFY pgrst, 'reload schema';
