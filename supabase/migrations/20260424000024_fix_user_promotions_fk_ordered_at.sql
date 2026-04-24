-- Fix 1: user_promotions.user_id FK — was pointing to auth.users, should be public.users
ALTER TABLE public.user_promotions
  DROP CONSTRAINT IF EXISTS user_promotions_user_id_fkey;

ALTER TABLE public.user_promotions
  ADD CONSTRAINT user_promotions_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;

-- Fix 2: refresh_user_metrics — use ordered_at for date calculations so
-- backdated seed orders produce realistic days_since_last_order & frequency.
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
    o.user_id                                                         AS user_id,
    MAX(COALESCE(o.ordered_at, o.created_at))                         AS last_order_at,
    COUNT(*)                                                          AS total_orders,
    ROUND(AVG(o.total_amount)::NUMERIC, 2)                           AS avg_order_value,
    EXTRACT(DAY FROM
      (now() - MAX(COALESCE(o.ordered_at, o.created_at)))
    )::INT                                                            AS days_since_last_order,
    ROUND(
      (COUNT(*)::FLOAT
        / GREATEST(
            EXTRACT(DAY FROM
              (now() - MIN(COALESCE(o.ordered_at, o.created_at)))
            )::FLOAT / 7.0,
            1
          ))::NUMERIC, 4
    )                                                                 AS order_frequency,
    now()                                                             AS updated_at
  FROM public.orders o
  WHERE o.status IN ('delivered', 'completed')
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
  INSERT INTO public.user_metrics (user_id, segment)
  SELECT u.id, 'new'
  FROM public.users u
  WHERE NOT EXISTS (
    SELECT 1 FROM public.user_metrics m WHERE m.user_id = u.id
  )
  ON CONFLICT DO NOTHING;
END;
$$;
