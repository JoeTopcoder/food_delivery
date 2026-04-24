CREATE OR REPLACE FUNCTION public.refresh_user_metrics()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.user_metrics (user_id, last_order_at, total_orders, avg_order_value, days_since_last_order, order_frequency, updated_at)
  SELECT
    o.user_id,
    MAX(COALESCE(o.ordered_at, o.created_at)),
    COUNT(*),
    ROUND(AVG(o.total_amount)::NUMERIC, 2),
    EXTRACT(DAY FROM (now() - MAX(COALESCE(o.ordered_at, o.created_at))))::INT,
    ROUND((COUNT(*)::FLOAT / GREATEST(EXTRACT(DAY FROM (now() - MIN(COALESCE(o.ordered_at, o.created_at))))::FLOAT / 7.0, 1))::NUMERIC, 4),
    now()
  FROM public.orders o
  WHERE o.status IN ('delivered','completed') AND o.user_id IS NOT NULL
  GROUP BY o.user_id
  ON CONFLICT (user_id) DO UPDATE SET
    last_order_at=EXCLUDED.last_order_at,
    total_orders=EXCLUDED.total_orders,
    avg_order_value=EXCLUDED.avg_order_value,
    days_since_last_order=EXCLUDED.days_since_last_order,
    order_frequency=EXCLUDED.order_frequency,
    updated_at=EXCLUDED.updated_at;

  INSERT INTO public.user_metrics (user_id, segment)
  SELECT u.id, 'new'
  FROM public.users u
  WHERE NOT EXISTS (SELECT 1 FROM public.user_metrics m WHERE m.user_id = u.id)
  ON CONFLICT DO NOTHING;
END;
$$;