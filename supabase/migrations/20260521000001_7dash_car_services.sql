-- =============================================================================
-- 7Dash Services — Car Wash / Detailing Marketplace
-- Migration: 20260521000001_7dash_car_services.sql
-- =============================================================================
-- Idempotent: all DDL uses IF NOT EXISTS / CREATE OR REPLACE.
-- Depends on existing tables: users (public), auth.users, wallets,
--   wallet_transactions, payments.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. car_service_categories
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.car_service_categories (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT        NOT NULL,
  icon_name    TEXT,
  description  TEXT,
  is_active    BOOLEAN     NOT NULL DEFAULT TRUE,
  sort_order   INT         NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.car_service_categories ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_car_service_categories_sort
  ON public.car_service_categories (sort_order);
CREATE INDEX IF NOT EXISTS idx_car_service_categories_active
  ON public.car_service_categories (is_active);

-- RLS Policies
DO $$ BEGIN
  -- Any authenticated user can read
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_categories'
      AND policyname = 'categories_select_authenticated'
  ) THEN
    CREATE POLICY categories_select_authenticated
      ON public.car_service_categories
      FOR SELECT
      TO authenticated
      USING (TRUE);
  END IF;

  -- Admin full access
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_categories'
      AND policyname = 'categories_admin_all'
  ) THEN
    CREATE POLICY categories_admin_all
      ON public.car_service_categories
      FOR ALL
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
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 2. car_service_providers
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.car_service_providers (
  id                      UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                 UUID           NOT NULL UNIQUE REFERENCES auth.users (id) ON DELETE CASCADE,
  business_name           TEXT           NOT NULL,
  bio                     TEXT,
  profile_image_url       TEXT,
  banner_image_url        TEXT,
  rating                  NUMERIC(3,2)   NOT NULL DEFAULT 0,
  total_reviews           INT            NOT NULL DEFAULT 0,
  total_bookings          INT            NOT NULL DEFAULT 0,
  is_active               BOOLEAN        NOT NULL DEFAULT TRUE,
  is_verified             BOOLEAN        NOT NULL DEFAULT FALSE,
  service_area_radius_km  NUMERIC        NOT NULL DEFAULT 20,
  base_location_lat       NUMERIC,
  base_location_lng       NUMERIC,
  base_location_address   TEXT,
  stripe_account_id       TEXT,
  stripe_payouts_enabled  BOOLEAN        NOT NULL DEFAULT FALSE,
  created_at              TIMESTAMPTZ    NOT NULL DEFAULT now(),
  updated_at              TIMESTAMPTZ    NOT NULL DEFAULT now()
);

ALTER TABLE public.car_service_providers ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_car_service_providers_user_id
  ON public.car_service_providers (user_id);
CREATE INDEX IF NOT EXISTS idx_car_service_providers_active
  ON public.car_service_providers (is_active);
CREATE INDEX IF NOT EXISTS idx_car_service_providers_rating
  ON public.car_service_providers (rating DESC);

-- RLS Policies
DO $$ BEGIN
  -- Any authenticated user can read active providers
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_providers'
      AND policyname = 'providers_select_authenticated'
  ) THEN
    CREATE POLICY providers_select_authenticated
      ON public.car_service_providers
      FOR SELECT
      TO authenticated
      USING (TRUE);
  END IF;

  -- Provider manages their own record
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_providers'
      AND policyname = 'providers_insert_own'
  ) THEN
    CREATE POLICY providers_insert_own
      ON public.car_service_providers
      FOR INSERT
      TO authenticated
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_providers'
      AND policyname = 'providers_update_own'
  ) THEN
    CREATE POLICY providers_update_own
      ON public.car_service_providers
      FOR UPDATE
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;

  -- Admin full access
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_providers'
      AND policyname = 'providers_admin_all'
  ) THEN
    CREATE POLICY providers_admin_all
      ON public.car_service_providers
      FOR ALL
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
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. car_service_offerings
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.car_service_offerings (
  id               UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id      UUID           NOT NULL REFERENCES public.car_service_providers (id) ON DELETE CASCADE,
  category_id      UUID           NOT NULL REFERENCES public.car_service_categories (id) ON DELETE RESTRICT,
  name             TEXT           NOT NULL,
  description      TEXT,
  duration_minutes INT            NOT NULL DEFAULT 60,
  base_price       NUMERIC(10,2)  NOT NULL,
  is_active        BOOLEAN        NOT NULL DEFAULT TRUE,
  created_at       TIMESTAMPTZ    NOT NULL DEFAULT now()
);

ALTER TABLE public.car_service_offerings ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_car_service_offerings_provider_id
  ON public.car_service_offerings (provider_id);
CREATE INDEX IF NOT EXISTS idx_car_service_offerings_category_id
  ON public.car_service_offerings (category_id);
CREATE INDEX IF NOT EXISTS idx_car_service_offerings_active
  ON public.car_service_offerings (is_active);

-- RLS Policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_offerings'
      AND policyname = 'offerings_select_authenticated'
  ) THEN
    CREATE POLICY offerings_select_authenticated
      ON public.car_service_offerings
      FOR SELECT
      TO authenticated
      USING (TRUE);
  END IF;

  -- Provider manages their own offerings
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_offerings'
      AND policyname = 'offerings_provider_insert'
  ) THEN
    CREATE POLICY offerings_provider_insert
      ON public.car_service_offerings
      FOR INSERT
      TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_offerings'
      AND policyname = 'offerings_provider_update'
  ) THEN
    CREATE POLICY offerings_provider_update
      ON public.car_service_offerings
      FOR UPDATE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_offerings'
      AND policyname = 'offerings_provider_delete'
  ) THEN
    CREATE POLICY offerings_provider_delete
      ON public.car_service_offerings
      FOR DELETE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  -- Admin full access
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_offerings'
      AND policyname = 'offerings_admin_all'
  ) THEN
    CREATE POLICY offerings_admin_all
      ON public.car_service_offerings
      FOR ALL
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
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 4. car_service_bookings
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.car_service_bookings (
  id                        UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_number            TEXT           UNIQUE NOT NULL DEFAULT '',  -- populated by trigger
  customer_id               UUID           NOT NULL REFERENCES auth.users (id) ON DELETE RESTRICT,
  provider_id               UUID           NOT NULL REFERENCES public.car_service_providers (id) ON DELETE RESTRICT,
  offering_id               UUID           NOT NULL REFERENCES public.car_service_offerings (id) ON DELETE RESTRICT,
  status                    TEXT           NOT NULL DEFAULT 'pending'
                              CHECK (status IN (
                                'pending', 'confirmed', 'provider_en_route',
                                'arrived', 'in_progress', 'completed',
                                'cancelled', 'no_show'
                              )),
  scheduled_at              TIMESTAMPTZ    NOT NULL,
  service_address           TEXT           NOT NULL,
  service_lat               NUMERIC,
  service_lng               NUMERIC,
  vehicle_make              TEXT,
  vehicle_model             TEXT,
  vehicle_color             TEXT,
  vehicle_plate             TEXT,
  subtotal                  NUMERIC(10,2)  NOT NULL,
  platform_fee              NUMERIC(10,2)  NOT NULL DEFAULT 0,
  service_fee               NUMERIC(10,2)  NOT NULL DEFAULT 0,
  total_amount              NUMERIC(10,2)  NOT NULL,
  payment_method            TEXT           NOT NULL DEFAULT 'card',
  payment_status            TEXT           NOT NULL DEFAULT 'pending'
                              CHECK (payment_status IN (
                                'pending', 'authorized', 'paid', 'failed', 'refunded'
                              )),
  stripe_payment_intent_id  TEXT,
  provider_notes            TEXT,
  customer_notes            TEXT,
  cancellation_reason       TEXT,
  cancelled_by              TEXT,
  provider_lat              NUMERIC,
  provider_lng              NUMERIC,
  started_at                TIMESTAMPTZ,
  completed_at              TIMESTAMPTZ,
  created_at                TIMESTAMPTZ    NOT NULL DEFAULT now(),
  updated_at                TIMESTAMPTZ    NOT NULL DEFAULT now()
);

ALTER TABLE public.car_service_bookings ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_car_service_bookings_customer_id
  ON public.car_service_bookings (customer_id);
CREATE INDEX IF NOT EXISTS idx_car_service_bookings_provider_id
  ON public.car_service_bookings (provider_id);
CREATE INDEX IF NOT EXISTS idx_car_service_bookings_offering_id
  ON public.car_service_bookings (offering_id);
CREATE INDEX IF NOT EXISTS idx_car_service_bookings_status
  ON public.car_service_bookings (status);
CREATE INDEX IF NOT EXISTS idx_car_service_bookings_scheduled_at
  ON public.car_service_bookings (scheduled_at);
CREATE INDEX IF NOT EXISTS idx_car_service_bookings_payment_status
  ON public.car_service_bookings (payment_status);

-- RLS Policies
DO $$ BEGIN
  -- Customer sees their own bookings
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_bookings'
      AND policyname = 'bookings_select_customer'
  ) THEN
    CREATE POLICY bookings_select_customer
      ON public.car_service_bookings
      FOR SELECT
      TO authenticated
      USING (customer_id = auth.uid());
  END IF;

  -- Provider sees bookings assigned to their provider record
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_bookings'
      AND policyname = 'bookings_select_provider'
  ) THEN
    CREATE POLICY bookings_select_provider
      ON public.car_service_bookings
      FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  -- Provider can update their bookings (status changes, notes, location)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_bookings'
      AND policyname = 'bookings_update_provider'
  ) THEN
    CREATE POLICY bookings_update_provider
      ON public.car_service_bookings
      FOR UPDATE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  -- Customer can update their own bookings (e.g., cancellation)
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_bookings'
      AND policyname = 'bookings_update_customer'
  ) THEN
    CREATE POLICY bookings_update_customer
      ON public.car_service_bookings
      FOR UPDATE
      TO authenticated
      USING (customer_id = auth.uid())
      WITH CHECK (customer_id = auth.uid());
  END IF;

  -- Authenticated customers can create bookings
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_bookings'
      AND policyname = 'bookings_insert_customer'
  ) THEN
    CREATE POLICY bookings_insert_customer
      ON public.car_service_bookings
      FOR INSERT
      TO authenticated
      WITH CHECK (customer_id = auth.uid());
  END IF;

  -- Admin sees and manages all
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_bookings'
      AND policyname = 'bookings_admin_all'
  ) THEN
    CREATE POLICY bookings_admin_all
      ON public.car_service_bookings
      FOR ALL
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
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 5. car_service_reviews
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.car_service_reviews (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id   UUID        NOT NULL UNIQUE REFERENCES public.car_service_bookings (id) ON DELETE CASCADE,
  customer_id  UUID        NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  provider_id  UUID        NOT NULL REFERENCES public.car_service_providers (id) ON DELETE CASCADE,
  rating       INT         NOT NULL CHECK (rating BETWEEN 1 AND 5),
  comment      TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.car_service_reviews ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_car_service_reviews_booking_id
  ON public.car_service_reviews (booking_id);
CREATE INDEX IF NOT EXISTS idx_car_service_reviews_provider_id
  ON public.car_service_reviews (provider_id);
CREATE INDEX IF NOT EXISTS idx_car_service_reviews_customer_id
  ON public.car_service_reviews (customer_id);

-- RLS Policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_reviews'
      AND policyname = 'reviews_select_authenticated'
  ) THEN
    CREATE POLICY reviews_select_authenticated
      ON public.car_service_reviews
      FOR SELECT
      TO authenticated
      USING (TRUE);
  END IF;

  -- Only the customer who made the booking can insert a review
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_reviews'
      AND policyname = 'reviews_insert_customer'
  ) THEN
    CREATE POLICY reviews_insert_customer
      ON public.car_service_reviews
      FOR INSERT
      TO authenticated
      WITH CHECK (
        customer_id = auth.uid()
        AND EXISTS (
          SELECT 1 FROM public.car_service_bookings b
          WHERE b.id = booking_id
            AND b.customer_id = auth.uid()
            AND b.status = 'completed'
        )
      );
  END IF;

  -- Customer can update their own review
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_reviews'
      AND policyname = 'reviews_update_customer'
  ) THEN
    CREATE POLICY reviews_update_customer
      ON public.car_service_reviews
      FOR UPDATE
      TO authenticated
      USING (customer_id = auth.uid())
      WITH CHECK (customer_id = auth.uid());
  END IF;

  -- Admin full access
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_reviews'
      AND policyname = 'reviews_admin_all'
  ) THEN
    CREATE POLICY reviews_admin_all
      ON public.car_service_reviews
      FOR ALL
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
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 6. car_service_provider_availability
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.car_service_provider_availability (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id  UUID        NOT NULL REFERENCES public.car_service_providers (id) ON DELETE CASCADE,
  day_of_week  INT         NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),
  start_time   TIME        NOT NULL,
  end_time     TIME        NOT NULL,
  is_active    BOOLEAN     NOT NULL DEFAULT TRUE,
  CONSTRAINT chk_time_order CHECK (end_time > start_time)
);

ALTER TABLE public.car_service_provider_availability ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_car_service_availability_provider_id
  ON public.car_service_provider_availability (provider_id);
CREATE INDEX IF NOT EXISTS idx_car_service_availability_day
  ON public.car_service_provider_availability (day_of_week);

-- RLS Policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_provider_availability'
      AND policyname = 'availability_select_authenticated'
  ) THEN
    CREATE POLICY availability_select_authenticated
      ON public.car_service_provider_availability
      FOR SELECT
      TO authenticated
      USING (TRUE);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_provider_availability'
      AND policyname = 'availability_provider_insert'
  ) THEN
    CREATE POLICY availability_provider_insert
      ON public.car_service_provider_availability
      FOR INSERT
      TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_provider_availability'
      AND policyname = 'availability_provider_update'
  ) THEN
    CREATE POLICY availability_provider_update
      ON public.car_service_provider_availability
      FOR UPDATE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_provider_availability'
      AND policyname = 'availability_provider_delete'
  ) THEN
    CREATE POLICY availability_provider_delete
      ON public.car_service_provider_availability
      FOR DELETE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_provider_availability'
      AND policyname = 'availability_admin_all'
  ) THEN
    CREATE POLICY availability_admin_all
      ON public.car_service_provider_availability
      FOR ALL
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
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 7. car_service_provider_images
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.car_service_provider_images (
  id           UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id  UUID        NOT NULL REFERENCES public.car_service_providers (id) ON DELETE CASCADE,
  image_url    TEXT        NOT NULL,
  is_primary   BOOLEAN     NOT NULL DEFAULT FALSE,
  sort_order   INT         NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.car_service_provider_images ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_car_service_provider_images_provider_id
  ON public.car_service_provider_images (provider_id);
CREATE INDEX IF NOT EXISTS idx_car_service_provider_images_primary
  ON public.car_service_provider_images (provider_id, is_primary);

-- RLS Policies
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_provider_images'
      AND policyname = 'provider_images_select_authenticated'
  ) THEN
    CREATE POLICY provider_images_select_authenticated
      ON public.car_service_provider_images
      FOR SELECT
      TO authenticated
      USING (TRUE);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_provider_images'
      AND policyname = 'provider_images_provider_insert'
  ) THEN
    CREATE POLICY provider_images_provider_insert
      ON public.car_service_provider_images
      FOR INSERT
      TO authenticated
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_provider_images'
      AND policyname = 'provider_images_provider_update'
  ) THEN
    CREATE POLICY provider_images_provider_update
      ON public.car_service_provider_images
      FOR UPDATE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_provider_images'
      AND policyname = 'provider_images_provider_delete'
  ) THEN
    CREATE POLICY provider_images_provider_delete
      ON public.car_service_provider_images
      FOR DELETE
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_provider_images'
      AND policyname = 'provider_images_admin_all'
  ) THEN
    CREATE POLICY provider_images_admin_all
      ON public.car_service_provider_images
      FOR ALL
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
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 8. car_service_payouts
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.car_service_payouts (
  id                  UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id         UUID           NOT NULL REFERENCES public.car_service_providers (id) ON DELETE RESTRICT,
  booking_id          UUID           NOT NULL REFERENCES public.car_service_bookings (id) ON DELETE RESTRICT,
  amount              NUMERIC(10,2)  NOT NULL,
  stripe_transfer_id  TEXT,
  status              TEXT           NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending', 'in_transit', 'paid', 'failed', 'cancelled')),
  created_at          TIMESTAMPTZ    NOT NULL DEFAULT now()
);

ALTER TABLE public.car_service_payouts ENABLE ROW LEVEL SECURITY;

-- Indexes
CREATE INDEX IF NOT EXISTS idx_car_service_payouts_provider_id
  ON public.car_service_payouts (provider_id);
CREATE INDEX IF NOT EXISTS idx_car_service_payouts_booking_id
  ON public.car_service_payouts (booking_id);
CREATE INDEX IF NOT EXISTS idx_car_service_payouts_status
  ON public.car_service_payouts (status);

-- RLS Policies
DO $$ BEGIN
  -- Provider sees their own payouts
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_payouts'
      AND policyname = 'payouts_select_provider'
  ) THEN
    CREATE POLICY payouts_select_provider
      ON public.car_service_payouts
      FOR SELECT
      TO authenticated
      USING (
        EXISTS (
          SELECT 1 FROM public.car_service_providers p
          WHERE p.id = provider_id AND p.user_id = auth.uid()
        )
      );
  END IF;

  -- Admin sees and manages all payouts
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'car_service_payouts'
      AND policyname = 'payouts_admin_all'
  ) THEN
    CREATE POLICY payouts_admin_all
      ON public.car_service_payouts
      FOR ALL
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
  END IF;
END $$;

-- =============================================================================
-- TRIGGER FUNCTIONS
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Booking number generator: CS-YYYYMMDD-XXXXX
-- Generates a random 5-character alphanumeric suffix.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.generate_car_service_booking_number()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_date_str  TEXT;
  v_suffix    TEXT;
  v_candidate TEXT;
  v_attempts  INT := 0;
BEGIN
  -- Only generate if not already set (idempotent on upsert scenarios)
  IF NEW.booking_number IS NOT NULL AND NEW.booking_number <> '' THEN
    RETURN NEW;
  END IF;

  v_date_str := TO_CHAR(NOW() AT TIME ZONE 'UTC', 'YYYYMMDD');

  LOOP
    -- Build a 5-character alphanumeric suffix from random bytes
    v_suffix := UPPER(
      SUBSTRING(
        REPLACE(REPLACE(encode(gen_random_bytes(6), 'base64'), '+', 'A'), '/', 'B'),
        1, 5
      )
    );
    v_candidate := 'CS-' || v_date_str || '-' || v_suffix;

    -- Exit once we have a unique number (extremely unlikely to collide)
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.car_service_bookings
      WHERE booking_number = v_candidate
    );

    v_attempts := v_attempts + 1;
    IF v_attempts > 10 THEN
      -- Fallback: append microseconds to guarantee uniqueness
      v_candidate := 'CS-' || v_date_str || '-' || LPAD(
        (EXTRACT(MICROSECONDS FROM clock_timestamp())::BIGINT % 100000)::TEXT,
        5, '0'
      );
      EXIT;
    END IF;
  END LOOP;

  NEW.booking_number := v_candidate;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_car_service_booking_number
  ON public.car_service_bookings;

CREATE TRIGGER trg_car_service_booking_number
  BEFORE INSERT ON public.car_service_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.generate_car_service_booking_number();

-- ---------------------------------------------------------------------------
-- updated_at maintenance — bookings
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_car_service_booking_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_car_service_booking_updated_at
  ON public.car_service_bookings;

CREATE TRIGGER trg_car_service_booking_updated_at
  BEFORE UPDATE ON public.car_service_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.set_car_service_booking_updated_at();

-- ---------------------------------------------------------------------------
-- updated_at maintenance — providers
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.set_car_service_provider_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_car_service_provider_updated_at
  ON public.car_service_providers;

CREATE TRIGGER trg_car_service_provider_updated_at
  BEFORE UPDATE ON public.car_service_providers
  FOR EACH ROW
  EXECUTE FUNCTION public.set_car_service_provider_updated_at();

-- ---------------------------------------------------------------------------
-- On booking completed → increment provider total_bookings
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_car_service_booking_completed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Only react when transitioning INTO 'completed'
  IF (OLD.status IS DISTINCT FROM 'completed') AND (NEW.status = 'completed') THEN
    -- Stamp completion time if not already set
    IF NEW.completed_at IS NULL THEN
      NEW.completed_at := now();
    END IF;

    -- Increment provider booking count and recalculate rating from reviews
    UPDATE public.car_service_providers
    SET
      total_bookings = total_bookings + 1,
      rating = COALESCE((
        SELECT ROUND(AVG(r.rating)::NUMERIC, 2)
        FROM public.car_service_reviews r
        WHERE r.provider_id = NEW.provider_id
      ), rating),
      total_reviews = (
        SELECT COUNT(*)
        FROM public.car_service_reviews r
        WHERE r.provider_id = NEW.provider_id
      ),
      updated_at = now()
    WHERE id = NEW.provider_id;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_car_service_booking_completed
  ON public.car_service_bookings;

CREATE TRIGGER trg_car_service_booking_completed
  BEFORE UPDATE ON public.car_service_bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_car_service_booking_completed();

-- ---------------------------------------------------------------------------
-- On new review → recalculate provider rating & review count
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.update_provider_rating_on_review()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_avg_rating NUMERIC(3,2);
  v_count      INT;
BEGIN
  SELECT
    ROUND(AVG(rating)::NUMERIC, 2),
    COUNT(*)
  INTO v_avg_rating, v_count
  FROM public.car_service_reviews
  WHERE provider_id = NEW.provider_id;

  UPDATE public.car_service_providers
  SET
    rating        = COALESCE(v_avg_rating, 0),
    total_reviews = v_count,
    updated_at    = now()
  WHERE id = NEW.provider_id;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_update_provider_rating_on_review
  ON public.car_service_reviews;

CREATE TRIGGER trg_update_provider_rating_on_review
  AFTER INSERT ON public.car_service_reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_provider_rating_on_review();

-- =============================================================================
-- SEED DATA — service categories
-- =============================================================================
INSERT INTO public.car_service_categories
  (name, icon_name, description, is_active, sort_order)
VALUES
  (
    'Exterior Wash',
    'local_car_wash',
    'Professional exterior hand wash and rinse. Removes dirt, grime, and road residue for a clean, streak-free finish.',
    TRUE, 1
  ),
  (
    'Interior Detail',
    'airline_seat_recline_normal',
    'Full interior deep-clean including vacuuming, wipe-downs, stain treatment, and odour elimination.',
    TRUE, 2
  ),
  (
    'Full Detail',
    'star',
    'The complete package — exterior wash plus interior detail, leaving your vehicle showroom-ready inside and out.',
    TRUE, 3
  ),
  (
    'Wax & Polish',
    'auto_awesome',
    'Machine polish to remove light scratches and swirl marks, followed by a protective wax coat for lasting shine.',
    TRUE, 4
  ),
  (
    'Engine Clean',
    'settings',
    'Degreasing and detailing of the engine bay for improved aesthetics, easier maintenance, and early fault detection.',
    TRUE, 5
  )
ON CONFLICT DO NOTHING;
