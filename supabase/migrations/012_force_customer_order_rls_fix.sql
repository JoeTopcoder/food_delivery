-- Force-reset customer address/order RLS so authenticated users can
-- add their own addresses and place their own orders.

-- --------------------------------------------------------------------
-- Grants required for Supabase authenticated users
-- --------------------------------------------------------------------
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.user_addresses TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.orders TO authenticated;
GRANT SELECT, INSERT ON public.order_items TO authenticated;

-- --------------------------------------------------------------------
-- Ensure RLS is enabled
-- --------------------------------------------------------------------
ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

-- --------------------------------------------------------------------
-- Drop existing customer-facing policies so we can replace them cleanly
-- --------------------------------------------------------------------
DROP POLICY IF EXISTS "users_read_own_addresses" ON public.user_addresses;
DROP POLICY IF EXISTS "users_insert_own_addresses" ON public.user_addresses;
DROP POLICY IF EXISTS "users_update_own_addresses" ON public.user_addresses;
DROP POLICY IF EXISTS "users_delete_own_addresses" ON public.user_addresses;
DROP POLICY IF EXISTS "customer_addresses_select_own" ON public.user_addresses;
DROP POLICY IF EXISTS "customer_addresses_insert_own" ON public.user_addresses;
DROP POLICY IF EXISTS "customer_addresses_update_own" ON public.user_addresses;
DROP POLICY IF EXISTS "customer_addresses_delete_own" ON public.user_addresses;

DROP POLICY IF EXISTS "users_read_accessible_orders" ON public.orders;
DROP POLICY IF EXISTS "users_insert_own_orders" ON public.orders;
DROP POLICY IF EXISTS "users_update_accessible_orders" ON public.orders;
DROP POLICY IF EXISTS "customers_select_own_orders" ON public.orders;
DROP POLICY IF EXISTS "customers_insert_own_orders" ON public.orders;
DROP POLICY IF EXISTS "customers_update_own_orders" ON public.orders;

DROP POLICY IF EXISTS "users_read_accessible_order_items" ON public.order_items;
DROP POLICY IF EXISTS "users_insert_own_order_items" ON public.order_items;
DROP POLICY IF EXISTS "customers_select_own_order_items" ON public.order_items;
DROP POLICY IF EXISTS "customers_insert_own_order_items" ON public.order_items;

-- --------------------------------------------------------------------
-- Customer address policies
-- --------------------------------------------------------------------
CREATE POLICY "customer_addresses_select_own"
ON public.user_addresses
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "customer_addresses_insert_own"
ON public.user_addresses
FOR INSERT
TO authenticated
WITH CHECK (user_id = auth.uid());

CREATE POLICY "customer_addresses_update_own"
ON public.user_addresses
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

CREATE POLICY "customer_addresses_delete_own"
ON public.user_addresses
FOR DELETE
TO authenticated
USING (user_id = auth.uid());

-- --------------------------------------------------------------------
-- Customer order policies
-- --------------------------------------------------------------------
CREATE POLICY "customers_select_own_orders"
ON public.orders
FOR SELECT
TO authenticated
USING (user_id = auth.uid());

CREATE POLICY "customers_insert_own_orders"
ON public.orders
FOR INSERT
TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND restaurant_id IS NOT NULL
  AND subtotal IS NOT NULL
  AND delivery_fee IS NOT NULL
  AND total_amount IS NOT NULL
  AND delivery_address IS NOT NULL
  AND payment_status IS NOT NULL
);

CREATE POLICY "customers_update_own_orders"
ON public.orders
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- --------------------------------------------------------------------
-- Customer order item policies
-- --------------------------------------------------------------------
CREATE POLICY "customers_select_own_order_items"
ON public.order_items
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.id = order_items.order_id
      AND o.user_id = auth.uid()
  )
);

CREATE POLICY "customers_insert_own_order_items"
ON public.order_items
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.id = order_items.order_id
      AND o.user_id = auth.uid()
  )
);