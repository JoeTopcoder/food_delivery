-- Analytics "Trend" and "Retention" were empty because daily_metrics and
-- retention_metrics are never populated (no job ever wrote to them). These
-- functions aggregate the real orders/users into those tables, a backfill runs
-- them over history, and a daily cron keeps them current.

-- ── Daily metrics (DAU / new users / orders / revenue / AOV per day) ─────────
CREATE OR REPLACE FUNCTION public.refresh_daily_metrics(p_days int DEFAULT 180)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  INSERT INTO public.daily_metrics (date, dau, new_users, total_orders, revenue, avg_order_value, is_mock_data)
  SELECT g::date,
    (SELECT count(DISTINCT o.user_id)::int FROM public.orders o
       WHERE COALESCE(o.ordered_at,o.created_at)::date = g::date AND o.status <> 'cancelled'),
    (SELECT count(*)::int FROM public.users u WHERE u.created_at::date = g::date),
    (SELECT count(*)::int FROM public.orders o
       WHERE COALESCE(o.ordered_at,o.created_at)::date = g::date AND o.status <> 'cancelled'),
    COALESCE((SELECT sum(o.total_amount) FROM public.orders o
       WHERE COALESCE(o.ordered_at,o.created_at)::date = g::date AND o.status <> 'cancelled'), 0),
    COALESCE((SELECT ROUND(avg(o.total_amount)::numeric, 2) FROM public.orders o
       WHERE COALESCE(o.ordered_at,o.created_at)::date = g::date AND o.status <> 'cancelled'), 0),
    false
  FROM generate_series(CURRENT_DATE - p_days, CURRENT_DATE, interval '1 day') g
  ON CONFLICT (date) DO UPDATE SET
    dau = EXCLUDED.dau, new_users = EXCLUDED.new_users,
    total_orders = EXCLUDED.total_orders, revenue = EXCLUDED.revenue,
    avg_order_value = EXCLUDED.avg_order_value;
$$;

-- ── Retention (D1 / D7 / D30 by signup-day cohort) ──────────────────────────
-- retained = users who signed up on cohort_date and placed an order on
-- cohort_date + N. Only complete cohorts (cohort_date + N <= today) are written.
CREATE OR REPLACE FUNCTION public.refresh_retention_metrics(p_days int DEFAULT 180)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  INSERT INTO public.retention_metrics (cohort_date, day, cohort_size, retained_users, is_mock_data)
  SELECT c.cohort_date, n.day, c.cohort_size,
    (SELECT count(DISTINCT o.user_id)::int
       FROM public.orders o JOIN public.users u ON u.id = o.user_id
      WHERE u.created_at::date = c.cohort_date
        AND COALESCE(o.ordered_at,o.created_at)::date = c.cohort_date + n.day
        AND o.status <> 'cancelled'),
    false
  FROM (
    SELECT u.created_at::date AS cohort_date, count(*)::int AS cohort_size
    FROM public.users u
    WHERE u.created_at::date >= CURRENT_DATE - p_days
    GROUP BY u.created_at::date
  ) c
  CROSS JOIN (VALUES (1),(7),(30)) n(day)
  WHERE c.cohort_date + n.day <= CURRENT_DATE
  ON CONFLICT (cohort_date, day) DO UPDATE SET
    cohort_size = EXCLUDED.cohort_size, retained_users = EXCLUDED.retained_users;
$$;

-- Wrapper the cron calls.
CREATE OR REPLACE FUNCTION public.refresh_analytics_metrics()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  PERFORM public.refresh_daily_metrics(180);
  PERFORM public.refresh_retention_metrics(180);
END;
$$;

-- Backfill now.
SELECT public.refresh_analytics_metrics();

-- Daily refresh at 05:15 UTC.
SELECT cron.schedule('refresh_analytics_metrics_daily', '15 5 * * *',
  'SELECT public.refresh_analytics_metrics();');

NOTIFY pgrst, 'reload schema';
