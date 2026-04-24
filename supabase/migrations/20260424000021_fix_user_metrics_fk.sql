-- Fix user_metrics FK + refresh_user_metrics stub insert
-- The FK was resolved to public.users at migration time.
-- The stub insert was selecting from auth.users which may include
-- auth accounts without a public.users profile row.

-- 1. Drop the current FK (may reference auth.users or public.users)
ALTER TABLE public.user_metrics
  DROP CONSTRAINT IF EXISTS user_metrics_user_id_fkey;

-- 2. Re-add pointing explicitly to public.users
ALTER TABLE public.user_metrics
  ADD CONSTRAINT user_metrics_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- 3. Recreate refresh_user_metrics with public.users in the stub insert
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

  -- Stub 'new' row for users in public.users who have never ordered.
  -- Uses public.users (not auth.users) to respect the FK constraint.
  INSERT INTO public.user_metrics (user_id, segment)
  SELECT u.id, 'new'
  FROM public.users u
  WHERE NOT EXISTS (
    SELECT 1 FROM public.user_metrics m WHERE m.user_id = u.id
  )
  ON CONFLICT DO NOTHING;
END;
$$;
