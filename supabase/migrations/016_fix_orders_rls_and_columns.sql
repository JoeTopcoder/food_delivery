-- ====================================================================
-- Migration 016: Fix orders RLS policy and add missing columns
-- ====================================================================

-- 1. Add missing columns to orders table that Flutter model expects
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS notes TEXT;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS discount DOUBLE PRECISION DEFAULT 0;
-- Fix: if discount was previously created as NUMERIC, convert to DOUBLE PRECISION
-- (PostgREST returns NUMERIC as strings, breaking Dart JSON deserialization)
ALTER TABLE public.orders ALTER COLUMN discount TYPE double precision USING discount::double precision;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS food_rating INTEGER;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS delivery_rating INTEGER;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS packaging_rating INTEGER;
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS review_photo_url TEXT;

-- 2. Add missing column to order_items table
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS notes TEXT;

-- 3. Make order_items.subtotal nullable (not always provided on insert)
ALTER TABLE public.order_items ALTER COLUMN subtotal DROP NOT NULL;
ALTER TABLE public.order_items ALTER COLUMN subtotal SET DEFAULT 0;

-- 4. Fix orders RLS: simplify the INSERT policy
--    The overly strict WITH CHECK was blocking inserts.
DROP POLICY IF EXISTS "customers_insert_own_orders" ON public.orders;
CREATE POLICY "customers_insert_own_orders"
ON public.orders
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

-- 5. Ensure restaurant owners and drivers can also read orders
DROP POLICY IF EXISTS "restaurant_owners_select_orders" ON public.orders;
CREATE POLICY "restaurant_owners_select_orders"
ON public.orders
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.restaurants r
    WHERE r.id = orders.restaurant_id AND r.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "drivers_select_assigned_orders" ON public.orders;
CREATE POLICY "drivers_select_assigned_orders"
ON public.orders
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.drivers d
    WHERE d.id = orders.driver_id AND d.user_id = auth.uid()
  )
);

-- 6. Restaurant owners can update orders (status changes)
DROP POLICY IF EXISTS "restaurant_owners_update_orders" ON public.orders;
CREATE POLICY "restaurant_owners_update_orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.restaurants r
    WHERE r.id = orders.restaurant_id AND r.owner_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.restaurants r
    WHERE r.id = orders.restaurant_id AND r.owner_id = auth.uid()
  )
);

-- 7. Drivers can update orders they are assigned to
DROP POLICY IF EXISTS "drivers_update_assigned_orders" ON public.orders;
CREATE POLICY "drivers_update_assigned_orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.drivers d
    WHERE d.id = orders.driver_id AND d.user_id = auth.uid()
  )
)
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.drivers d
    WHERE d.id = orders.driver_id AND d.user_id = auth.uid()
  )
);

-- 8. Fix order_items RLS: restaurant owners and drivers can also read
DROP POLICY IF EXISTS "restaurant_owners_select_order_items" ON public.order_items;
CREATE POLICY "restaurant_owners_select_order_items"
ON public.order_items
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.restaurants r ON r.id = o.restaurant_id
    WHERE o.id = order_items.order_id AND r.owner_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "drivers_select_order_items" ON public.order_items;
CREATE POLICY "drivers_select_order_items"
ON public.order_items
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.drivers d ON d.id = o.driver_id
    WHERE o.id = order_items.order_id AND d.user_id = auth.uid()
  )
);

-- 9. Ensure GRANT on order_item_sides for authenticated users
GRANT SELECT, INSERT ON public.order_item_sides TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.menu_item_sides TO authenticated;
