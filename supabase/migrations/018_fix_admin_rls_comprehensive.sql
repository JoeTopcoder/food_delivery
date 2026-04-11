-- Migration 018: Comprehensive admin RLS fix
-- Creates a SECURITY DEFINER function to check admin status (bypasses RLS)
-- and adds admin SELECT policies to ALL tables missing them.

-- ============================================================
-- 1. Create a safe admin-check function (SECURITY DEFINER)
--    This runs as the function owner, bypassing RLS entirely,
--    so it won't cause recursive policy evaluation.
-- ============================================================
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.users
    WHERE id = auth.uid()
      AND role = 'admin'
  );
$$;

-- Grant execute to authenticated
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;

-- ============================================================
-- 2. Drop and recreate existing admin policies to use is_admin()
-- ============================================================

-- users
DROP POLICY IF EXISTS "admin_select_all_users" ON public.users;
DROP POLICY IF EXISTS "admin_update_users" ON public.users;

CREATE POLICY "admin_select_all_users" ON public.users
  FOR SELECT TO authenticated
  USING (is_admin());

CREATE POLICY "admin_update_users" ON public.users
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- drivers
DROP POLICY IF EXISTS "admin_select_all_drivers" ON public.drivers;
DROP POLICY IF EXISTS "admin_update_drivers" ON public.drivers;

CREATE POLICY "admin_select_all_drivers" ON public.drivers
  FOR SELECT TO authenticated
  USING (is_admin());

CREATE POLICY "admin_update_drivers" ON public.drivers
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- restaurants
DROP POLICY IF EXISTS "admin_select_all_restaurants" ON public.restaurants;
DROP POLICY IF EXISTS "admin_update_restaurants" ON public.restaurants;

CREATE POLICY "admin_select_all_restaurants" ON public.restaurants
  FOR SELECT TO authenticated
  USING (is_admin());

CREATE POLICY "admin_update_restaurants" ON public.restaurants
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- orders
DROP POLICY IF EXISTS "admin_select_all_orders" ON public.orders;

CREATE POLICY "admin_select_all_orders" ON public.orders
  FOR SELECT TO authenticated
  USING (is_admin());

CREATE POLICY "admin_update_orders" ON public.orders
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- ============================================================
-- 3. Add admin policies to ALL remaining tables
-- ============================================================

-- order_items
CREATE POLICY "admin_select_all_order_items" ON public.order_items
  FOR SELECT TO authenticated
  USING (is_admin());

-- order_item_sides
CREATE POLICY "admin_select_all_order_item_sides" ON public.order_item_sides
  FOR SELECT TO authenticated
  USING (is_admin());

-- menus
CREATE POLICY "admin_select_all_menus" ON public.menus
  FOR SELECT TO authenticated
  USING (is_admin());

-- menu_item_sides
CREATE POLICY "admin_select_all_menu_item_sides" ON public.menu_item_sides
  FOR SELECT TO authenticated
  USING (is_admin());

-- reviews
CREATE POLICY "admin_select_all_reviews" ON public.reviews
  FOR SELECT TO authenticated
  USING (is_admin());

-- payments
CREATE POLICY "admin_select_all_payments" ON public.payments
  FOR SELECT TO authenticated
  USING (is_admin());

-- notifications
CREATE POLICY "admin_select_all_notifications" ON public.notifications
  FOR SELECT TO authenticated
  USING (is_admin());

-- chat_messages
CREATE POLICY "admin_select_all_chat_messages" ON public.chat_messages
  FOR SELECT TO authenticated
  USING (is_admin());

CREATE POLICY "admin_insert_chat_messages" ON public.chat_messages
  FOR INSERT TO authenticated
  WITH CHECK (is_admin());

-- loyalty_accounts
CREATE POLICY "admin_select_all_loyalty_accounts" ON public.loyalty_accounts
  FOR SELECT TO authenticated
  USING (is_admin());

-- loyalty_transactions
CREATE POLICY "admin_select_all_loyalty_transactions" ON public.loyalty_transactions
  FOR SELECT TO authenticated
  USING (is_admin());

-- driver_locations
CREATE POLICY "admin_select_all_driver_locations" ON public.driver_locations
  FOR SELECT TO authenticated
  USING (is_admin());

-- user_addresses
CREATE POLICY "admin_select_all_user_addresses" ON public.user_addresses
  FOR SELECT TO authenticated
  USING (is_admin());

-- order_issues (already has admin_view_issues with USING(true) — drop and recreate properly)
DROP POLICY IF EXISTS "admin_view_issues" ON public.order_issues;

CREATE POLICY "admin_select_all_order_issues" ON public.order_issues
  FOR SELECT TO authenticated
  USING (is_admin());

CREATE POLICY "admin_update_order_issues" ON public.order_issues
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

-- promo_codes: update existing policies to use is_admin()
DROP POLICY IF EXISTS "admin_manage_promos" ON public.promo_codes;
DROP POLICY IF EXISTS "admins_delete_promos" ON public.promo_codes;
DROP POLICY IF EXISTS "admins_insert_promos" ON public.promo_codes;
DROP POLICY IF EXISTS "admins_update_promos" ON public.promo_codes;

CREATE POLICY "admin_select_promos" ON public.promo_codes
  FOR SELECT TO authenticated
  USING (is_admin());

CREATE POLICY "admin_insert_promos" ON public.promo_codes
  FOR INSERT TO authenticated
  WITH CHECK (is_admin());

CREATE POLICY "admin_update_promos" ON public.promo_codes
  FOR UPDATE TO authenticated
  USING (is_admin())
  WITH CHECK (is_admin());

CREATE POLICY "admin_delete_promos" ON public.promo_codes
  FOR DELETE TO authenticated
  USING (is_admin());

-- ============================================================
-- 4. Update the old current_user_is_admin() to call is_admin()
-- ============================================================
CREATE OR REPLACE FUNCTION public.current_user_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT public.is_admin();
$$;
