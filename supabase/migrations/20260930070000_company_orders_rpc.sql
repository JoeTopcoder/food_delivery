-- Dashboard read: a company admin's SPONSORED orders only (never employees'
-- personal orders). SECURITY DEFINER so it can join users for the employee name
-- while exposing only non-sensitive fields; gated to the company admin / HotBite.
CREATE OR REPLACE FUNCTION public.company_orders(p_company_id uuid, p_date date DEFAULT NULL)
  RETURNS TABLE (
    order_id uuid, restaurant_order_number text, ordered_at timestamptz,
    employee_name text, restaurant_name text, status text,
    delivery_cents int, service_cents int, total_company_cents int,
    charge_status text, sponsorship_date date)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT o.id,
         coalesce(o.restaurant_order_number, left(o.id::text,8)),
         o.ordered_at,
         u.name, r.name, o.status,
         coalesce(o.company_delivery_cents,0),
         coalesce(o.company_service_cents,0),
         coalesce(o.company_delivery_cents,0) + coalesce(o.company_service_cents,0),
         coalesce(o.company_charge_status,'estimated'),
         o.company_sponsorship_date
  FROM public.orders o
  JOIN public.users u ON u.id = o.user_id
  LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.company_id = p_company_id
    AND o.is_company_sponsored
    AND (p_date IS NULL OR o.company_sponsorship_date = p_date)
    AND (public.is_company_admin(p_company_id) OR public.is_admin())
  ORDER BY o.ordered_at DESC;
$$;

REVOKE ALL ON FUNCTION public.company_orders(uuid,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_orders(uuid,date) TO authenticated;

NOTIFY pgrst, 'reload schema';
