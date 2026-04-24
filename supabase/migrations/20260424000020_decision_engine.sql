-- ─────────────────────────────────────────────────────────────
-- DECISION ENGINE — User Intelligence + Promotions + Dynamic Pricing
-- Migration: 20260424000020_decision_engine.sql
-- ─────────────────────────────────────────────────────────────

-- ── 1. user_metrics ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_metrics (
  user_id               UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  last_order_at         TIMESTAMP WITH TIME ZONE,
  total_orders          INT          NOT NULL DEFAULT 0,
  avg_order_value       NUMERIC(12,2) NOT NULL DEFAULT 0,
  days_since_last_order INT          NOT NULL DEFAULT 0,
  order_frequency       FLOAT        NOT NULL DEFAULT 0, -- orders per week
  segment               TEXT         NOT NULL DEFAULT 'new'
                          CHECK (segment IN ('new','active','at_risk','loyal')),
  updated_at            TIMESTAMP WITH TIME ZONE DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_user_metrics_segment ON public.user_metrics(segment);

-- ── 2. promotions ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.promotions (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  type             TEXT   NOT NULL CHECK (type IN ('discount','free_delivery','fixed')),
  value            NUMERIC(12,2) NOT NULL DEFAULT 0,
  min_order        NUMERIC(12,2) NOT NULL DEFAULT 0,
  target_segment   TEXT   NOT NULL CHECK (target_segment IN ('new','active','at_risk','loyal','all')),
  label            TEXT,            -- human-readable e.g. "comeback offer"
  active           BOOLEAN NOT NULL DEFAULT true,
  created_at       TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ── 3. user_promotions ───────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_promotions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  promotion_id UUID NOT NULL REFERENCES public.promotions(id) ON DELETE CASCADE,
  sent_at      TIMESTAMP WITH TIME ZONE DEFAULT now(),
  used         BOOLEAN NOT NULL DEFAULT false,
  used_at      TIMESTAMP WITH TIME ZONE,
  UNIQUE (user_id, promotion_id)  -- prevent duplicate assignments
);

CREATE INDEX IF NOT EXISTS idx_user_promotions_user   ON public.user_promotions(user_id, used);
CREATE INDEX IF NOT EXISTS idx_user_promotions_promo  ON public.user_promotions(promotion_id);

-- ── 4. experiments (A/B) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.experiments (
  id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name      TEXT   NOT NULL UNIQUE,
  variant_a JSONB  NOT NULL DEFAULT '{}',
  variant_b JSONB  NOT NULL DEFAULT '{}',
  active    BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ── 5. promotion_results (feedback loop) ─────────────────────
CREATE TABLE IF NOT EXISTS public.promotion_results (
  promotion_id       UUID PRIMARY KEY REFERENCES public.promotions(id) ON DELETE CASCADE,
  sent               INT          NOT NULL DEFAULT 0,
  used               INT          NOT NULL DEFAULT 0,
  revenue_generated  NUMERIC(12,2) NOT NULL DEFAULT 0,
  conversion_rate    NUMERIC(5,4)  GENERATED ALWAYS AS (
                       CASE WHEN sent = 0 THEN 0
                            ELSE ROUND((used::NUMERIC / sent), 4)
                       END
                     ) STORED,
  updated_at         TIMESTAMP WITH TIME ZONE DEFAULT now()
);

-- ─────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────

ALTER TABLE public.user_metrics        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_promotions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.experiments         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promotion_results   ENABLE ROW LEVEL SECURITY;

-- user_metrics: users read own; admin reads all
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='user_read_own_metrics' AND tablename='user_metrics') THEN
    CREATE POLICY user_read_own_metrics ON public.user_metrics
      FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='admin_manage_user_metrics' AND tablename='user_metrics') THEN
    CREATE POLICY admin_manage_user_metrics ON public.user_metrics
      FOR ALL USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin')
      );
  END IF;
END $$;

-- promotions: all authenticated users can read active ones; admin manages
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='read_active_promotions' AND tablename='promotions') THEN
    CREATE POLICY read_active_promotions ON public.promotions
      FOR SELECT USING (active = true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='admin_manage_promotions' AND tablename='promotions') THEN
    CREATE POLICY admin_manage_promotions ON public.promotions
      FOR ALL USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin')
      );
  END IF;
END $$;

-- user_promotions: users read own; admin all
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='user_read_own_promos' AND tablename='user_promotions') THEN
    CREATE POLICY user_read_own_promos ON public.user_promotions
      FOR SELECT USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='user_mark_used' AND tablename='user_promotions') THEN
    CREATE POLICY user_mark_used ON public.user_promotions
      FOR UPDATE USING (user_id = auth.uid());
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='admin_manage_user_promotions' AND tablename='user_promotions') THEN
    CREATE POLICY admin_manage_user_promotions ON public.user_promotions
      FOR ALL USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin')
      );
  END IF;
END $$;

-- experiments: admin only
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='admin_manage_experiments' AND tablename='experiments') THEN
    CREATE POLICY admin_manage_experiments ON public.experiments
      FOR ALL USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin')
      );
  END IF;
END $$;

-- promotion_results: admin only
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE policyname='admin_read_promotion_results' AND tablename='promotion_results') THEN
    CREATE POLICY admin_read_promotion_results ON public.promotion_results
      FOR SELECT USING (
        EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin')
      );
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- FUNCTION: refresh_user_metrics — rebuilds all per-user signals
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.refresh_user_metrics()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.user_metrics (
    user_id,
    last_order_at,
    total_orders,
    avg_order_value,
    days_since_last_order,
    order_frequency,
    updated_at
  )
  SELECT
    o.user_id                                                       AS user_id,
    MAX(o.created_at)                                               AS last_order_at,
    COUNT(*)                                                        AS total_orders,
    ROUND(AVG(o.total_amount)::NUMERIC, 2)                         AS avg_order_value,
    EXTRACT(DAY FROM (now() - MAX(o.created_at)))::INT             AS days_since_last_order,
    ROUND(
      (COUNT(*)::FLOAT
        / GREATEST(
            EXTRACT(DAY FROM (now() - MIN(o.created_at)))::FLOAT / 7.0,
            1
          ))::NUMERIC, 4
    )                                                               AS order_frequency,
    now()                                                           AS updated_at
  FROM public.orders o
  WHERE o.status IN ('delivered','completed')
    AND o.user_id IS NOT NULL
  GROUP BY o.user_id
  ON CONFLICT (user_id) DO UPDATE
    SET last_order_at         = EXCLUDED.last_order_at,
        total_orders          = EXCLUDED.total_orders,
        avg_order_value       = EXCLUDED.avg_order_value,
        days_since_last_order = EXCLUDED.days_since_last_order,
        order_frequency       = EXCLUDED.order_frequency,
        updated_at            = EXCLUDED.updated_at;

  -- insert 'new' stub for users who have never ordered
  INSERT INTO public.user_metrics (user_id, segment)
  SELECT u.id, 'new'
  FROM auth.users u
  WHERE NOT EXISTS (SELECT 1 FROM public.user_metrics m WHERE m.user_id = u.id)
  ON CONFLICT DO NOTHING;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- FUNCTION: update_user_segments — classifies users
-- ─────────────────────────────────────────────────────────────
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
    updated_at = now();
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- FUNCTION: generate_promotions — decision engine
-- Only assigns a promotion if the user doesn't already have one unused
-- ─────────────────────────────────────────────────────────────
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

-- ─────────────────────────────────────────────────────────────
-- FUNCTION: get_dynamic_delivery_fee — demand/supply multiplier
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_dynamic_delivery_fee(base_fee NUMERIC)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  multiplier       NUMERIC := 1.0;
  recent_orders    INT;
  online_drivers   INT;
BEGIN
  -- High demand: > 50 orders in last hour
  SELECT COUNT(*) INTO recent_orders
  FROM public.orders
  WHERE created_at > now() - INTERVAL '1 hour';

  IF recent_orders > 50 THEN
    multiplier := multiplier + 0.3;
  ELSIF recent_orders > 25 THEN
    multiplier := multiplier + 0.15;
  END IF;

  -- Low supply: < 10 online drivers
  SELECT COUNT(*) INTO online_drivers
  FROM public.drivers
  WHERE status = 'online';

  IF online_drivers < 5 THEN
    multiplier := multiplier + 0.25;
  ELSIF online_drivers < 10 THEN
    multiplier := multiplier + 0.10;
  END IF;

  -- Cap at 2x
  multiplier := LEAST(multiplier, 2.0);

  RETURN ROUND(base_fee * multiplier, 2);
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- FUNCTION: get_segment_distribution — admin panel feed
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_segment_distribution()
RETURNS TABLE(segment TEXT, user_count BIGINT, pct NUMERIC)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
AS $$
DECLARE
  total BIGINT;
BEGIN
  SELECT COUNT(*) INTO total FROM public.user_metrics;
  RETURN QUERY
  SELECT
    m.segment,
    COUNT(*)                                                    AS user_count,
    CASE WHEN total = 0 THEN 0
         ELSE ROUND(COUNT(*)::NUMERIC * 100 / total, 1)
    END AS pct
  FROM public.user_metrics m
  GROUP BY m.segment
  ORDER BY user_count DESC;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- FUNCTION: get_promotion_stats — admin panel feed
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_promotion_stats()
RETURNS TABLE(
  promotion_id    UUID,
  label           TEXT,
  type            TEXT,
  value           NUMERIC,
  target_segment  TEXT,
  sent            INT,
  used            INT,
  conversion_rate NUMERIC,
  revenue_generated NUMERIC
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id                          AS promotion_id,
    p.label,
    p.type,
    p.value,
    p.target_segment,
    COALESCE(pr.sent, 0)          AS sent,
    COALESCE(pr.used, 0)          AS used,
    COALESCE(pr.conversion_rate, 0) AS conversion_rate,
    COALESCE(pr.revenue_generated, 0) AS revenue_generated
  FROM public.promotions p
  LEFT JOIN public.promotion_results pr ON pr.promotion_id = p.id
  WHERE p.active = true
  ORDER BY COALESCE(pr.revenue_generated, 0) DESC;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- FUNCTION: run_decision_engine — single call to refresh all
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.run_decision_engine()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM public.refresh_user_metrics();
  PERFORM public.update_user_segments();
  PERFORM public.generate_promotions();
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- GRANTS
-- ─────────────────────────────────────────────────────────────
GRANT EXECUTE ON FUNCTION public.get_dynamic_delivery_fee(NUMERIC)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_segment_distribution()          TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_promotion_stats()               TO authenticated;
GRANT EXECUTE ON FUNCTION public.run_decision_engine()               TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_user_metrics()              TO service_role;
GRANT EXECUTE ON FUNCTION public.update_user_segments()              TO service_role;
GRANT EXECUTE ON FUNCTION public.generate_promotions()               TO service_role;

-- ─────────────────────────────────────────────────────────────
-- CRON (pg_cron, skipped gracefully if not enabled)
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    -- Full engine run: daily at 01:00 UTC
    PERFORM cron.schedule(
      'decision_engine_daily',
      '0 1 * * *',
      'SELECT public.run_decision_engine()'
    );
  END IF;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- SEED: default promotions for each segment
-- ─────────────────────────────────────────────────────────────
INSERT INTO public.promotions (type, value, min_order, target_segment, label, active)
VALUES
  ('discount',        15, 500,    'new',     'Welcome offer — 15% off first order',      true),
  ('discount',        20, 800,   'at_risk',  'We miss you! 20% off, come back',           true),
  ('free_delivery',    0,  0,    'loyal',    'Thank you! Free delivery on your next order', true),
  ('discount',        10, 1000,  'active',   '10% off this weekend',                      false)
ON CONFLICT DO NOTHING;
