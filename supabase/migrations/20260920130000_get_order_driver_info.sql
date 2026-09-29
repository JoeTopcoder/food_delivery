-- Restaurants (and customers) need to see who the assigned driver is, but the
-- drivers table is RLS-locked to admin/self. This SECURITY DEFINER RPC returns
-- the assigned driver's public info for a given order, but ONLY to callers who
-- are allowed to see that order: the order's restaurant owner, the order's
-- customer, or an admin. Returns no rows otherwise.

CREATE OR REPLACE FUNCTION public.get_order_driver_info(p_order_id uuid)
RETURNS TABLE(
  driver_id uuid,
  name text,
  phone text,
  profile_image_url text,
  vehicle_type text,
  rating numeric
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_order RECORD;
BEGIN
  SELECT o.driver_id, o.user_id, o.restaurant_id
    INTO v_order
  FROM orders o
  WHERE o.id = p_order_id;

  IF v_order IS NULL OR v_order.driver_id IS NULL THEN
    RETURN;
  END IF;

  -- Authorisation: caller must be the order's customer, the restaurant owner,
  -- or an admin. (When v_uid is NULL — service role / direct SQL — allow.)
  IF v_uid IS NOT NULL
     AND v_uid <> v_order.user_id
     AND NOT EXISTS (
       SELECT 1 FROM restaurants r
       WHERE r.id = v_order.restaurant_id AND r.owner_id = v_uid
     )
     AND NOT EXISTS (
       SELECT 1 FROM users u WHERE u.id = v_uid AND u.role = 'admin'
     )
  THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT d.id,
         u.name,
         u.phone,
         u.profile_image_url,
         d.vehicle_type,
         d.rating::numeric
  FROM drivers d
  JOIN users u ON u.id = d.user_id
  WHERE d.id = v_order.driver_id;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_order_driver_info(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
