-- ─────────────────────────────────────────────────────────────
-- Analytics System
-- Tables: sessions, daily_metrics, retention_metrics
-- Functions: get_analytics_summary, get_dau_trend, get_retention,
--            get_top_restaurants, refresh_daily_metrics
-- ─────────────────────────────────────────────────────────────

-- 1. Sessions table (used for DAU tracking)
CREATE TABLE IF NOT EXISTS public.sessions (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        REFERENCES public.users(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_sessions_user_date
  ON public.sessions(user_id, created_at);

CREATE INDEX IF NOT EXISTS idx_sessions_date
  ON public.sessions(created_at);

-- RLS: only admins can read; sessions are inserted by app on login
ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_read_sessions" ON public.sessions;
CREATE POLICY "admin_read_sessions" ON public.sessions
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

DROP POLICY IF EXISTS "user_insert_own_session" ON public.sessions;
CREATE POLICY "user_insert_own_session" ON public.sessions
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- 2. Pre-computed daily metrics (populated by cron / refresh_daily_metrics)
CREATE TABLE IF NOT EXISTS public.daily_metrics (
  date            DATE    PRIMARY KEY,
  dau             INT     NOT NULL DEFAULT 0,
  new_users       INT     NOT NULL DEFAULT 0,
  total_orders    INT     NOT NULL DEFAULT 0,
  revenue         NUMERIC NOT NULL DEFAULT 0,
  avg_order_value NUMERIC NOT NULL DEFAULT 0
);

ALTER TABLE public.daily_metrics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_read_daily_metrics" ON public.daily_metrics;
CREATE POLICY "admin_read_daily_metrics" ON public.daily_metrics
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 3. Retention metrics (D1/D7/D30 per cohort date)
CREATE TABLE IF NOT EXISTS public.retention_metrics (
  cohort_date     DATE NOT NULL,
  day             INT  NOT NULL,
  retained_users  INT  NOT NULL DEFAULT 0,
  cohort_size     INT  NOT NULL DEFAULT 0,
  PRIMARY KEY (cohort_date, day)
);

ALTER TABLE public.retention_metrics ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_read_retention" ON public.retention_metrics;
CREATE POLICY "admin_read_retention" ON public.retention_metrics
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ─────────────────────────────────────────────────────────────
-- SQL FUNCTIONS
-- ─────────────────────────────────────────────────────────────

-- 4. Live analytics summary (today snapshot)
CREATE OR REPLACE FUNCTION public.get_analytics_summary()
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  result JSON;
  today DATE := CURRENT_DATE;
BEGIN
  SELECT json_build_object(
    'dau',
      (SELECT COUNT(DISTINCT user_id)
       FROM public.sessions
       WHERE created_at::date = today),
    'new_users',
      (SELECT COUNT(*)
       FROM public.users
       WHERE created_at::date = today),
    'orders_today',
      (SELECT COUNT(*)
       FROM public.orders
       WHERE created_at::date = today),
    'revenue_today',
      (SELECT COALESCE(SUM(total_amount), 0)
       FROM public.orders
       WHERE created_at::date = today AND status = 'delivered'),
    'aov_today',
      (SELECT COALESCE(AVG(total_amount), 0)
       FROM public.orders
       WHERE created_at::date = today AND status = 'delivered'),
    'orders_week',
      (SELECT COUNT(*)
       FROM public.orders
       WHERE created_at >= today - INTERVAL '7 days'),
    'revenue_week',
      (SELECT COALESCE(SUM(total_amount), 0)
       FROM public.orders
       WHERE created_at >= today - INTERVAL '7 days' AND status = 'delivered'),
    'orders_month',
      (SELECT COUNT(*)
       FROM public.orders
       WHERE created_at >= today - INTERVAL '30 days'),
    'revenue_month',
      (SELECT COALESCE(SUM(total_amount), 0)
       FROM public.orders
       WHERE created_at >= today - INTERVAL '30 days' AND status = 'delivered'),
    'completion_rate',
      (SELECT ROUND(
         COALESCE(
           100.0 * COUNT(*) FILTER (WHERE status = 'delivered') / NULLIF(COUNT(*), 0),
           0
         ), 1
       )
       FROM public.orders
       WHERE created_at >= today - INTERVAL '30 days')
  ) INTO result;

  RETURN result;
END;
$$;

-- 5. DAU trend — last N days from daily_metrics (falls back to live sessions)
CREATE OR REPLACE FUNCTION public.get_dau_trend(days_back INT DEFAULT 30)
RETURNS TABLE(trend_date DATE, dau INT, orders INT, revenue NUMERIC)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    d.date      AS trend_date,
    d.dau       AS dau,
    d.total_orders AS orders,
    d.revenue   AS revenue
  FROM public.daily_metrics d
  WHERE d.date >= CURRENT_DATE - days_back
  ORDER BY d.date ASC;
END;
$$;

-- 6. Retention: how many users from a cohort returned on day N
CREATE OR REPLACE FUNCTION public.get_retention(day_n INT DEFAULT 7)
RETURNS TABLE(cohort_date DATE, cohort_size INT, retained INT, rate NUMERIC)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    r.cohort_date,
    r.cohort_size,
    r.retained_users  AS retained,
    ROUND(
      100.0 * r.retained_users / NULLIF(r.cohort_size, 0), 1
    ) AS rate
  FROM public.retention_metrics r
  WHERE r.day = day_n
  ORDER BY r.cohort_date DESC
  LIMIT 14;
END;
$$;

-- 7. Top restaurants by revenue in last N days
CREATE OR REPLACE FUNCTION public.get_top_restaurants(days_back INT DEFAULT 30, row_limit INT DEFAULT 10)
RETURNS TABLE(restaurant_id UUID, restaurant_name TEXT, order_count BIGINT, revenue NUMERIC)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  SELECT
    o.restaurant_id,
    r.name AS restaurant_name,
    COUNT(o.id)           AS order_count,
    COALESCE(SUM(o.total_amount), 0) AS revenue
  FROM public.orders o
  JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.created_at >= CURRENT_DATE - days_back
    AND o.status = 'delivered'
  GROUP BY o.restaurant_id, r.name
  ORDER BY revenue DESC
  LIMIT row_limit;
END;
$$;

-- 8. Refresh / upsert daily_metrics for a given date (called by CRON or manually)
CREATE OR REPLACE FUNCTION public.refresh_daily_metrics(target_date DATE DEFAULT CURRENT_DATE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_dau             INT;
  v_new_users       INT;
  v_total_orders    INT;
  v_revenue         NUMERIC;
  v_aov             NUMERIC;
BEGIN
  -- DAU
  SELECT COUNT(DISTINCT user_id)
  INTO v_dau
  FROM public.sessions
  WHERE created_at::date = target_date;

  -- New users
  SELECT COUNT(*)
  INTO v_new_users
  FROM public.users
  WHERE created_at::date = target_date;

  -- Orders
  SELECT COUNT(*), COALESCE(SUM(total_amount), 0), COALESCE(AVG(total_amount), 0)
  INTO v_total_orders, v_revenue, v_aov
  FROM public.orders
  WHERE created_at::date = target_date AND status = 'delivered';

  INSERT INTO public.daily_metrics(date, dau, new_users, total_orders, revenue, avg_order_value)
  VALUES (target_date, v_dau, v_new_users, v_total_orders, v_revenue, v_aov)
  ON CONFLICT (date) DO UPDATE
    SET dau             = EXCLUDED.dau,
        new_users       = EXCLUDED.new_users,
        total_orders    = EXCLUDED.total_orders,
        revenue         = EXCLUDED.revenue,
        avg_order_value = EXCLUDED.avg_order_value;
END;
$$;

-- 9. Refresh retention cohorts for a past cohort date
CREATE OR REPLACE FUNCTION public.refresh_retention_cohort(cohort_date DATE)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_cohort_size INT;
BEGIN
  SELECT COUNT(*) INTO v_cohort_size
  FROM public.users
  WHERE created_at::date = cohort_date;

  IF v_cohort_size = 0 THEN RETURN; END IF;

  -- Upsert day 1, 7, 30
  INSERT INTO public.retention_metrics(cohort_date, day, retained_users, cohort_size)
  SELECT
    cohort_date,
    day_n,
    (
      SELECT COUNT(DISTINCT o.user_id)
      FROM public.orders o
      JOIN public.users u ON u.id = o.user_id
      WHERE u.created_at::date = cohort_date
        AND o.created_at::date = cohort_date + day_n
    ),
    v_cohort_size
  FROM unnest(ARRAY[1, 7, 30]) AS day_n
  ON CONFLICT (cohort_date, day) DO UPDATE
    SET retained_users = EXCLUDED.retained_users,
        cohort_size    = EXCLUDED.cohort_size;
END;
$$;

-- ─────────────────────────────────────────────────────────────
-- CRON JOBS (pg_cron) — skipped gracefully if extension not enabled
-- To enable: Supabase Dashboard → Database → Extensions → pg_cron
-- Then run manually:
--   SELECT cron.schedule('daily_metrics_refresh',  '5 0 * * *', $$SELECT public.refresh_daily_metrics(CURRENT_DATE - 1)$$);
--   SELECT cron.schedule('hourly_metrics_refresh', '0 * * * *', $$SELECT public.refresh_daily_metrics(CURRENT_DATE)$$);
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.schedule(
      'daily_metrics_refresh',
      '5 0 * * *',
      'SELECT public.refresh_daily_metrics(CURRENT_DATE - 1)'
    );
    PERFORM cron.schedule(
      'hourly_metrics_refresh',
      '0 * * * *',
      'SELECT public.refresh_daily_metrics(CURRENT_DATE)'
    );
  END IF;
END;
$$;

-- Grant execute to service role
GRANT EXECUTE ON FUNCTION public.get_analytics_summary()             TO service_role;
GRANT EXECUTE ON FUNCTION public.get_dau_trend(INT)                  TO service_role;
GRANT EXECUTE ON FUNCTION public.get_retention(INT)                  TO service_role;
GRANT EXECUTE ON FUNCTION public.get_top_restaurants(INT, INT)       TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_daily_metrics(DATE)         TO service_role;
GRANT EXECUTE ON FUNCTION public.refresh_retention_cohort(DATE)      TO service_role;

-- Also grant to authenticated so admin users can call direct RPC
GRANT EXECUTE ON FUNCTION public.get_analytics_summary()             TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_dau_trend(INT)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_retention(INT)                  TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_top_restaurants(INT, INT)       TO authenticated;
