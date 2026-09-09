-- Migration: target history for the dashboard drill-down.
--
-- daily_targets has RLS and no SELECT policy by design — it is reached only
-- through SECURITY DEFINER RPCs — so the history view needs one too.
--
-- Joins each target to the actual for its day so hit/miss is answered from the
-- same actuals the KPI cards use, rather than recomputed differently here.

CREATE OR REPLACE FUNCTION public.admin_target_history(
  p_vertical TEXT DEFAULT 'food',
  p_limit    INT  DEFAULT 30
)
RETURNS TABLE (
  target_date     DATE,
  target_orders   INT,
  actual_orders   BIGINT,
  hit             BOOLEAN,
  source          TEXT,
  previous_target INT,
  notes           TEXT,
  created_at      TIMESTAMPTZ,
  superseded      BOOLEAN
)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;
  IF p_vertical NOT IN ('food','grocery') THEN
    RAISE EXCEPTION 'Invalid vertical %. Use food or grocery', p_vertical;
  END IF;
  -- Clamped rather than trusted: an unbounded limit from the client is a way
  -- to make the server do arbitrary work.
  p_limit := LEAST(GREATEST(COALESCE(p_limit, 30), 1), 365);

  RETURN QUERY
  SELECT dt.target_date,
         dt.target_orders,
         COALESCE(da.orders_count, 0)::bigint,
         -- A day with no target is neither hit nor missed; NULL says that,
         -- where false would claim a failure that was never set up.
         CASE WHEN dt.target_orders > 0
              THEN COALESCE(da.orders_count, 0) >= dt.target_orders
              ELSE NULL END,
         dt.source,
         prev.target_orders,
         dt.notes,
         dt.created_at,
         (dt.superseded_at IS NOT NULL)
  FROM public.daily_targets dt
  LEFT JOIN public.daily_actuals da
         ON da.target_date = dt.target_date AND da.vertical = dt.vertical
  LEFT JOIN public.daily_targets prev
         ON prev.id = dt.previous_target_id
  WHERE dt.vertical = p_vertical
  ORDER BY dt.target_date DESC, dt.created_at DESC
  LIMIT p_limit;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public.admin_target_history(TEXT, INT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_target_history(TEXT, INT)
  TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';
