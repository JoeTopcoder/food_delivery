-- Retention rates were flat 0 because refresh_retention_metrics counted a user as
-- "retained at day N" only if they ordered on the EXACT day (signup + N). With real,
-- low-frequency ordering nobody lands on the exact day, so every cohort read 0.
-- Standard product retention is cumulative/windowed: retained at day N = signed up in
-- the cohort AND placed an order within N days of signing up. This rewrites the job to
-- that definition and re-backfills.
CREATE OR REPLACE FUNCTION public.refresh_retention_metrics(p_days int DEFAULT 180)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
  INSERT INTO public.retention_metrics (cohort_date, day, cohort_size, retained_users, is_mock_data)
  SELECT c.cohort_date, n.day, c.cohort_size,
    (SELECT count(DISTINCT u.id)::int
       FROM public.users u
      WHERE u.created_at::date = c.cohort_date
        AND EXISTS (
          SELECT 1 FROM public.orders o
           WHERE o.user_id = u.id
             AND o.status <> 'cancelled'
             AND COALESCE(o.ordered_at,o.created_at)::date >  c.cohort_date
             AND COALESCE(o.ordered_at,o.created_at)::date <= c.cohort_date + n.day)),
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

-- Re-backfill with the corrected definition.
SELECT public.refresh_retention_metrics(180);

NOTIFY pgrst, 'reload schema';
