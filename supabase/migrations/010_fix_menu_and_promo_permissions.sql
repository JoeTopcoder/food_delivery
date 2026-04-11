-- Fix menu management and promo management permissions/schema mismatches.

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

-- --------------------------------------------------------------------
-- Promo codes table alignment for app-side fields
-- --------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.promo_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  description TEXT,
  discount_type TEXT NOT NULL CHECK (discount_type IN ('percentage', 'fixed')),
  discount_value DOUBLE PRECISION NOT NULL,
  min_order_amount DOUBLE PRECISION DEFAULT 0,
  max_uses INTEGER,
  usage_count INTEGER NOT NULL DEFAULT 0,
  expires_at TIMESTAMP WITH TIME ZONE,
  restaurant_id UUID REFERENCES public.restaurants(id) ON DELETE SET NULL,
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

ALTER TABLE public.promo_codes
  ADD COLUMN IF NOT EXISTS max_uses INTEGER,
  ADD COLUMN IF NOT EXISTS usage_count INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMP WITH TIME ZONE,
  ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW();

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'promo_codes'
      AND column_name = 'usage_limit'
  ) THEN
    EXECUTE '
      UPDATE public.promo_codes
      SET max_uses = COALESCE(max_uses, usage_limit)
      WHERE max_uses IS NULL
    ';
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'promo_codes'
      AND column_name = 'valid_until'
  ) THEN
    EXECUTE '
      UPDATE public.promo_codes
      SET expires_at = COALESCE(expires_at, valid_until)
      WHERE expires_at IS NULL
    ';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_promo_codes_code ON public.promo_codes(code);
CREATE INDEX IF NOT EXISTS idx_promo_codes_is_active ON public.promo_codes(is_active);
CREATE INDEX IF NOT EXISTS idx_promo_codes_expires_at ON public.promo_codes(expires_at);

-- --------------------------------------------------------------------
-- Promo usage RPC expected by the app
-- --------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.increment_promo_usage(promo_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.promo_codes
  SET usage_count = COALESCE(usage_count, 0) + 1,
      updated_at = NOW()
  WHERE id = promo_id;
END;
$$;

-- --------------------------------------------------------------------
-- Row level security and policies
-- --------------------------------------------------------------------
ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menus ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.promo_codes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "public_read_restaurants" ON public.restaurants;
CREATE POLICY "public_read_restaurants"
ON public.restaurants
FOR SELECT
USING (
  COALESCE(is_open, TRUE) = TRUE
  OR owner_id = auth.uid()
  OR public.current_user_is_admin()
);

DROP POLICY IF EXISTS "owners_insert_restaurants" ON public.restaurants;
CREATE POLICY "owners_insert_restaurants"
ON public.restaurants
FOR INSERT
WITH CHECK (
  owner_id = auth.uid()
  OR public.current_user_is_admin()
);

DROP POLICY IF EXISTS "owners_update_restaurants" ON public.restaurants;
CREATE POLICY "owners_update_restaurants"
ON public.restaurants
FOR UPDATE
USING (
  owner_id = auth.uid()
  OR public.current_user_is_admin()
)
WITH CHECK (
  owner_id = auth.uid()
  OR public.current_user_is_admin()
);

DROP POLICY IF EXISTS "public_read_menus" ON public.menus;
CREATE POLICY "public_read_menus"
ON public.menus
FOR SELECT
USING (
  COALESCE(is_available, TRUE) = TRUE
  OR public.current_user_owns_restaurant(restaurant_id)
  OR public.current_user_is_admin()
);

DROP POLICY IF EXISTS "owners_insert_menus" ON public.menus;
CREATE POLICY "owners_insert_menus"
ON public.menus
FOR INSERT
WITH CHECK (
  public.current_user_owns_restaurant(restaurant_id)
  OR public.current_user_is_admin()
);

DROP POLICY IF EXISTS "owners_update_menus" ON public.menus;
CREATE POLICY "owners_update_menus"
ON public.menus
FOR UPDATE
USING (
  public.current_user_owns_restaurant(restaurant_id)
  OR public.current_user_is_admin()
)
WITH CHECK (
  public.current_user_owns_restaurant(restaurant_id)
  OR public.current_user_is_admin()
);

DROP POLICY IF EXISTS "owners_delete_menus" ON public.menus;
CREATE POLICY "owners_delete_menus"
ON public.menus
FOR DELETE
USING (
  public.current_user_owns_restaurant(restaurant_id)
  OR public.current_user_is_admin()
);

DROP POLICY IF EXISTS "read_active_promos_or_admin_all" ON public.promo_codes;
CREATE POLICY "read_active_promos_or_admin_all"
ON public.promo_codes
FOR SELECT
USING (
  public.current_user_is_admin()
  OR COALESCE(is_active, TRUE) = TRUE
);

DROP POLICY IF EXISTS "admins_insert_promos" ON public.promo_codes;
CREATE POLICY "admins_insert_promos"
ON public.promo_codes
FOR INSERT
WITH CHECK (public.current_user_is_admin());

DROP POLICY IF EXISTS "admins_update_promos" ON public.promo_codes;
CREATE POLICY "admins_update_promos"
ON public.promo_codes
FOR UPDATE
USING (public.current_user_is_admin())
WITH CHECK (public.current_user_is_admin());

DROP POLICY IF EXISTS "admins_delete_promos" ON public.promo_codes;
CREATE POLICY "admins_delete_promos"
ON public.promo_codes
FOR DELETE
USING (public.current_user_is_admin());