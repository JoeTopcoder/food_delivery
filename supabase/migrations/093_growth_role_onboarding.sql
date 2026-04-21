-- Migration 093: Growth-focused role onboarding schema and RLS helpers

-- USERS: support role-first onboarding and nullable profile fields.
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS onboarding_completed boolean NOT NULL DEFAULT false;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS phone text;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS name text;

ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS email text;

-- Normalize role values and allow both legacy and new role names during transition.
DO $$
BEGIN
  UPDATE public.users
  SET role = 'customer'
  WHERE role = 'user';

  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'users_role_growth_check'
  ) THEN
    ALTER TABLE public.users
      ADD CONSTRAINT users_role_growth_check
      CHECK (role IN ('customer', 'driver', 'restaurant', 'admin'));
  END IF;
END $$;

-- DRIVERS: progressive onboarding flags.
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS license_plate text,
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS documents_uploaded boolean NOT NULL DEFAULT false;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'drivers_status_growth_check'
  ) THEN
    ALTER TABLE public.drivers
      ADD CONSTRAINT drivers_status_growth_check
      CHECK (status IN ('pending', 'approved'));
  END IF;
END $$;

-- RESTAURANTS: draft/active lifecycle and onboarding resume pointer.
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS status text DEFAULT 'draft',
  ADD COLUMN IF NOT EXISTS onboarding_step integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS stripe_account_id text,
  ADD COLUMN IF NOT EXISTS menu_image_url text;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'restaurants_status_growth_check'
  ) THEN
    ALTER TABLE public.restaurants
      ADD CONSTRAINT restaurants_status_growth_check
      CHECK (status IN ('draft', 'active'));
  END IF;
END $$;

-- MENU ITEMS: lightweight instant go-live table for restaurant quick setup.
CREATE TABLE IF NOT EXISTS public.menu_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  name text NOT NULL,
  price numeric(10,2) NOT NULL DEFAULT 0,
  image_url text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz
);

CREATE INDEX IF NOT EXISTS idx_menu_items_restaurant_id
  ON public.menu_items(restaurant_id);

-- RLS: keep access strictly role-owned.
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'menu_items' AND policyname = 'menu_items_owner_read_write'
  ) THEN
    CREATE POLICY menu_items_owner_read_write ON public.menu_items
    FOR ALL
    USING (
      EXISTS (
        SELECT 1
        FROM public.restaurants r
        WHERE r.id = menu_items.restaurant_id
          AND r.owner_id = auth.uid()
      )
    )
    WITH CHECK (
      EXISTS (
        SELECT 1
        FROM public.restaurants r
        WHERE r.id = menu_items.restaurant_id
          AND r.owner_id = auth.uid()
      )
    );
  END IF;
END $$;

-- Ensure users can only read/update their own row.
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'users' AND policyname = 'users_self_read'
  ) THEN
    CREATE POLICY users_self_read ON public.users
      FOR SELECT USING (id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'users' AND policyname = 'users_self_update'
  ) THEN
    CREATE POLICY users_self_update ON public.users
      FOR UPDATE USING (id = auth.uid())
      WITH CHECK (id = auth.uid());
  END IF;
END $$;

ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'drivers' AND policyname = 'drivers_self_read_write'
  ) THEN
    CREATE POLICY drivers_self_read_write ON public.drivers
    FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

ALTER TABLE public.restaurants ENABLE ROW LEVEL SECURITY;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'restaurants' AND policyname = 'restaurants_owner_read_write'
  ) THEN
    CREATE POLICY restaurants_owner_read_write ON public.restaurants
    FOR ALL
    USING (owner_id = auth.uid())
    WITH CHECK (owner_id = auth.uid());
  END IF;
END $$;
