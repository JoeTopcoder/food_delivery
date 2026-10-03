-- Admin order search: find ANY order (incl. old delivered ones beyond the
-- recent list) by full/partial Order ID, receipt number, or customer name/email.
-- Returns the same nested shape (restaurants/users/driver) the admin order cards
-- already consume, so the UI can render results identically. Admin-only.
CREATE OR REPLACE FUNCTION public.admin_search_orders(
  p_q text,
  p_statuses text[] DEFAULT NULL,
  p_limit int DEFAULT 50
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE v_rows jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin only';
  END IF;
  IF COALESCE(trim(p_q), '') = '' THEN RETURN '[]'::jsonb; END IF;

  SELECT COALESCE(jsonb_agg(x ORDER BY x->>'ordered_at' DESC), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT to_jsonb(o)
         || jsonb_build_object('restaurants',
              CASE WHEN r.id IS NULL THEN NULL
                   ELSE jsonb_build_object('name', r.name, 'store_type', r.store_type) END)
         || jsonb_build_object('users',
              CASE WHEN u.id IS NULL THEN NULL
                   ELSE jsonb_build_object('name', u.name, 'email', u.email, 'phone', u.phone) END)
         || jsonb_build_object('driver',
              CASE WHEN d.id IS NULL THEN NULL
                   ELSE jsonb_build_object('id', d.id, 'vehicle_type', d.vehicle_type,
                          'user', jsonb_build_object('name', du.name, 'phone', du.phone)) END) AS x
    FROM orders o
    LEFT JOIN restaurants r ON r.id = o.restaurant_id
    LEFT JOIN users u       ON u.id = o.user_id
    LEFT JOIN drivers d     ON d.id = o.driver_id
    LEFT JOIN users du      ON du.id = d.user_id
    WHERE (
        o.id::text ILIKE '%' || p_q || '%'
        OR COALESCE(o.receipt_number,'') ILIKE '%' || p_q || '%'
        OR COALESCE(u.name,'')  ILIKE '%' || p_q || '%'
        OR COALESCE(u.email,'') ILIKE '%' || p_q || '%'
        OR COALESCE(r.name,'')  ILIKE '%' || p_q || '%'
      )
      AND (p_statuses IS NULL OR array_length(p_statuses,1) IS NULL OR o.status = ANY(p_statuses))
    ORDER BY o.ordered_at DESC
    LIMIT GREATEST(1, LEAST(p_limit, 100))
  ) t;

  RETURN v_rows;
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_search_orders(text, text[], int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_search_orders(text, text[], int) TO authenticated;

NOTIFY pgrst, 'reload schema';
