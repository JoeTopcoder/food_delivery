-- Fix customer address creation and order placement.

-- --------------------------------------------------------------------
-- Helper functions for RLS checks
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.current_user_is_admin()
RETURNS BOOLEAN
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
      AND COALESCE(is_active, TRUE) = TRUE
  );
$$;

CREATE OR REPLACE FUNCTION public.current_user_owns_restaurant(target_restaurant_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.restaurants
    WHERE id = target_restaurant_id
      AND owner_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION public.current_user_can_read_order(target_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.orders o
    LEFT JOIN public.restaurants r ON r.id = o.restaurant_id
    LEFT JOIN public.drivers d ON d.id = o.driver_id
    WHERE o.id = target_order_id
      AND (
        o.user_id = auth.uid()
        OR r.owner_id = auth.uid()
        OR d.user_id = auth.uid()
        OR public.current_user_is_admin()
      )
  );
$$;

CREATE OR REPLACE FUNCTION public.current_user_can_insert_order_items(target_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.orders o
    WHERE o.id = target_order_id
      AND (
        o.user_id = auth.uid()
        OR public.current_user_is_admin()
      )
  );
$$;

-- --------------------------------------------------------------------
-- Address book table expected by the app
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_addresses (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  label TEXT NOT NULL DEFAULT 'Home',
  address TEXT NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  is_default BOOLEAN NOT NULL DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.user_addresses
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

CREATE INDEX IF NOT EXISTS idx_user_addresses_user_id ON public.user_addresses(user_id);
CREATE INDEX IF NOT EXISTS idx_user_addresses_default ON public.user_addresses(user_id, is_default);
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_addresses_one_default_per_user
  ON public.user_addresses(user_id)
  WHERE is_default = TRUE;

-- --------------------------------------------------------------------
-- Orders schema compatibility between migrations and schema.sql variants
-- --------------------------------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS discount DOUBLE PRECISION DEFAULT 0,
  ADD COLUMN IF NOT EXISTS discount_amount DOUBLE PRECISION DEFAULT 0,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS special_instructions TEXT,
  ADD COLUMN IF NOT EXISTS completed_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMP WITH TIME ZONE;

UPDATE public.orders
SET discount = COALESCE(discount, discount_amount, 0)
WHERE discount IS NULL;

UPDATE public.orders
SET discount_amount = COALESCE(discount_amount, discount, 0)
WHERE discount_amount IS NULL;

UPDATE public.orders
SET notes = COALESCE(notes, special_instructions)
WHERE notes IS NULL;

UPDATE public.orders
SET special_instructions = COALESCE(special_instructions, notes)
WHERE special_instructions IS NULL;

UPDATE public.orders
SET completed_at = COALESCE(completed_at, delivered_at)
WHERE completed_at IS NULL;

UPDATE public.orders
SET delivered_at = COALESCE(delivered_at, completed_at)
WHERE delivered_at IS NULL;

CREATE OR REPLACE FUNCTION public.sync_order_compat_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.discount := COALESCE(NEW.discount, NEW.discount_amount, 0);
  NEW.discount_amount := COALESCE(NEW.discount_amount, NEW.discount, 0);
  NEW.notes := COALESCE(NEW.notes, NEW.special_instructions);
  NEW.special_instructions := COALESCE(NEW.special_instructions, NEW.notes);
  NEW.completed_at := COALESCE(NEW.completed_at, NEW.delivered_at);
  NEW.delivered_at := COALESCE(NEW.delivered_at, NEW.completed_at);
  NEW.updated_at := NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_order_compat_columns ON public.orders;
CREATE TRIGGER trg_sync_order_compat_columns
BEFORE INSERT OR UPDATE ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.sync_order_compat_columns();

-- --------------------------------------------------------------------
-- Order items schema compatibility
-- --------------------------------------------------------------------
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS special_instructions TEXT,
  ADD COLUMN IF NOT EXISTS subtotal DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS item_description TEXT;

UPDATE public.order_items
SET notes = COALESCE(notes, special_instructions)
WHERE notes IS NULL;

UPDATE public.order_items
SET special_instructions = COALESCE(special_instructions, notes)
WHERE special_instructions IS NULL;

UPDATE public.order_items
SET subtotal = COALESCE(subtotal, price * quantity)
WHERE subtotal IS NULL;

CREATE OR REPLACE FUNCTION public.sync_order_item_compat_columns()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.notes := COALESCE(NEW.notes, NEW.special_instructions);
  NEW.special_instructions := COALESCE(NEW.special_instructions, NEW.notes);
  NEW.subtotal := COALESCE(NEW.subtotal, NEW.price * NEW.quantity);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_order_item_compat_columns ON public.order_items;
CREATE TRIGGER trg_sync_order_item_compat_columns
BEFORE INSERT OR UPDATE ON public.order_items
FOR EACH ROW
EXECUTE FUNCTION public.sync_order_item_compat_columns();

-- --------------------------------------------------------------------
-- RLS policies required by the app flows
-- --------------------------------------------------------------------
ALTER TABLE public.user_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_read_own_addresses" ON public.user_addresses;
CREATE POLICY "users_read_own_addresses"
ON public.user_addresses
FOR SELECT
USING (user_id = auth.uid() OR public.current_user_is_admin());

DROP POLICY IF EXISTS "users_insert_own_addresses" ON public.user_addresses;
CREATE POLICY "users_insert_own_addresses"
ON public.user_addresses
FOR INSERT
WITH CHECK (user_id = auth.uid() OR public.current_user_is_admin());

DROP POLICY IF EXISTS "users_update_own_addresses" ON public.user_addresses;
CREATE POLICY "users_update_own_addresses"
ON public.user_addresses
FOR UPDATE
USING (user_id = auth.uid() OR public.current_user_is_admin())
WITH CHECK (user_id = auth.uid() OR public.current_user_is_admin());

DROP POLICY IF EXISTS "users_delete_own_addresses" ON public.user_addresses;
CREATE POLICY "users_delete_own_addresses"
ON public.user_addresses
FOR DELETE
USING (user_id = auth.uid() OR public.current_user_is_admin());

DROP POLICY IF EXISTS "users_read_accessible_orders" ON public.orders;
CREATE POLICY "users_read_accessible_orders"
ON public.orders
FOR SELECT
USING (
  user_id = auth.uid()
  OR public.current_user_owns_restaurant(restaurant_id)
  OR public.current_user_is_admin()
  OR EXISTS (
    SELECT 1
    FROM public.drivers d
    WHERE d.id = driver_id
      AND d.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "users_insert_own_orders" ON public.orders;
CREATE POLICY "users_insert_own_orders"
ON public.orders
FOR INSERT
WITH CHECK (user_id = auth.uid() OR public.current_user_is_admin());

DROP POLICY IF EXISTS "users_update_accessible_orders" ON public.orders;
CREATE POLICY "users_update_accessible_orders"
ON public.orders
FOR UPDATE
USING (
  user_id = auth.uid()
  OR public.current_user_owns_restaurant(restaurant_id)
  OR public.current_user_is_admin()
  OR EXISTS (
    SELECT 1
    FROM public.drivers d
    WHERE d.id = driver_id
      AND d.user_id = auth.uid()
  )
)
WITH CHECK (
  user_id = auth.uid()
  OR public.current_user_owns_restaurant(restaurant_id)
  OR public.current_user_is_admin()
  OR EXISTS (
    SELECT 1
    FROM public.drivers d
    WHERE d.id = driver_id
      AND d.user_id = auth.uid()
  )
);

DROP POLICY IF EXISTS "users_read_accessible_order_items" ON public.order_items;
CREATE POLICY "users_read_accessible_order_items"
ON public.order_items
FOR SELECT
USING (public.current_user_can_read_order(order_id));

DROP POLICY IF EXISTS "users_insert_own_order_items" ON public.order_items;
CREATE POLICY "users_insert_own_order_items"
ON public.order_items
FOR INSERT
WITH CHECK (public.current_user_can_insert_order_items(order_id));