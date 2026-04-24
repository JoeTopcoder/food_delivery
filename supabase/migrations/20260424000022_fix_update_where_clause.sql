-- Fix: update_user_segments and promotion_results UPDATE need WHERE clauses
-- PostgREST rejects full-table UPDATEs without a predicate.

CREATE OR REPLACE FUNCTION public.update_user_segments()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.user_metrics
  SET segment =
    CASE
      WHEN total_orders = 0                THEN 'new'
      WHEN days_since_last_order > 14      THEN 'at_risk'
      WHEN order_frequency >= 2            THEN 'loyal'
      ELSE                                      'active'
    END,
    updated_at = now()
  WHERE user_id IS NOT NULL;
END;
$$;

-- Also fix generate_promotions — the promotion_results upsert's ON CONFLICT
-- UPDATE path also needs to avoid a bare UPDATE issue.
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
    ON CONFLICT DO NOTHING;
  END IF;

  -- Refresh promotion_results
  INSERT INTO public.promotion_results (promotion_id, sent, used, revenue_generated)
  SELECT
    up.promotion_id,
    COUNT(*)                                                  AS sent,
    COUNT(*) FILTER (WHERE up.used = true)                   AS used,
    COALESCE(SUM(o.total_amount) FILTER (WHERE up.used = true), 0) AS revenue_generated
  FROM public.user_promotions up
  LEFT JOIN public.orders o
    ON o.user_id   = up.user_id
   AND o.created_at >= up.sent_at
  WHERE up.promotion_id IS NOT NULL
  GROUP BY up.promotion_id
  ON CONFLICT (promotion_id) DO UPDATE
    SET sent               = EXCLUDED.sent,
        used               = EXCLUDED.used,
        revenue_generated  = EXCLUDED.revenue_generated,
        updated_at         = now();
END;
$$;
