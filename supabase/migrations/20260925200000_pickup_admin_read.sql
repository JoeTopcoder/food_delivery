-- Restaurant Pickup Coordinator — admin dashboard read.
CREATE OR REPLACE FUNCTION public.admin_pickup_overview(p_limit int DEFAULT 50)
RETURNS TABLE (
  call_id uuid, order_ref text, restaurant_name text, call_status text,
  outcome text, prep_underway boolean, confirmed_ready_at timestamptz,
  auto_ready_authorized boolean, delay_reported boolean,
  order_status text, expected_ready_at timestamptz,
  scheduled_ready_at timestamptz, scheduled_job_status text,
  queued_at timestamptz, completed_at timestamptz, notes text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  PERFORM public.require_admin();
  RETURN QUERY
  SELECT c.id, upper(substr(c.order_id::text,1,8)), r.name, c.status,
         c.outcome, c.prep_underway, c.confirmed_ready_at,
         c.auto_ready_authorized, c.delay_reported,
         o.status, o.expected_ready_at,
         j.run_at, j.status,
         c.queued_at, c.completed_at, c.notes
  FROM restaurant_pickup_calls c
  LEFT JOIN restaurants r ON r.id = c.restaurant_id
  LEFT JOIN orders o ON o.id = c.order_id
  LEFT JOIN LATERAL (
    SELECT run_at, status FROM restaurant_ready_jobs rj
    WHERE rj.order_id = c.order_id ORDER BY rj.created_at DESC LIMIT 1
  ) j ON true
  ORDER BY c.queued_at DESC
  LIMIT LEAST(GREATEST(p_limit,1),200);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_pickup_overview(int) TO authenticated;
NOTIFY pgrst, 'reload schema';
