-- ====================================================================
-- Migration 017: Admin driver management – RLS policies + vehicle_type fix
-- ====================================================================

-- 1. Fix vehicle_type CHECK constraint to include 'motorcycle'
ALTER TABLE public.drivers DROP CONSTRAINT IF EXISTS drivers_vehicle_type_check;
ALTER TABLE public.drivers ADD CONSTRAINT drivers_vehicle_type_check
  CHECK (vehicle_type IN ('bike', 'car', 'scooter', 'bicycle', 'motorcycle'));

-- 2. Admin can SELECT all users (role = 'admin' in public.users)
DROP POLICY IF EXISTS "admin_select_all_users" ON public.users;
CREATE POLICY "admin_select_all_users"
ON public.users
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);

-- 3. Admin can UPDATE users (ban/unban, role changes)
DROP POLICY IF EXISTS "admin_update_users" ON public.users;
CREATE POLICY "admin_update_users"
ON public.users
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);

-- 4. Admin can SELECT all drivers
DROP POLICY IF EXISTS "admin_select_all_drivers" ON public.drivers;
CREATE POLICY "admin_select_all_drivers"
ON public.drivers
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);

-- 5. Admin can UPDATE drivers (verify, reject, etc.)
DROP POLICY IF EXISTS "admin_update_drivers" ON public.drivers;
CREATE POLICY "admin_update_drivers"
ON public.drivers
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);

-- 6. Admin can SELECT all restaurants
DROP POLICY IF EXISTS "admin_select_all_restaurants" ON public.restaurants;
CREATE POLICY "admin_select_all_restaurants"
ON public.restaurants
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);

-- 7. Admin can UPDATE restaurants (verify, etc.)
DROP POLICY IF EXISTS "admin_update_restaurants" ON public.restaurants;
CREATE POLICY "admin_update_restaurants"
ON public.restaurants
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);

-- 8. Admin can SELECT all orders (for dashboard analytics)
DROP POLICY IF EXISTS "admin_select_all_orders" ON public.orders;
CREATE POLICY "admin_select_all_orders"
ON public.orders
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.users u
    WHERE u.id = auth.uid() AND u.role = 'admin'
  )
);

-- 9. Ensure GRANT permissions
GRANT SELECT, INSERT, UPDATE ON public.drivers TO authenticated;
GRANT SELECT, UPDATE ON public.users TO authenticated;
GRANT SELECT, UPDATE ON public.restaurants TO authenticated;
