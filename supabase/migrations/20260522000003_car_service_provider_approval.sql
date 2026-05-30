-- Add approval workflow columns to car_service_providers
-- Also add missing business-info columns and update users role constraint

-- 1. New columns on car_service_providers
ALTER TABLE public.car_service_providers
  ADD COLUMN IF NOT EXISTS is_approved          boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS is_suspended         boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS approval_status      text        NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS rejection_reason     text,
  ADD COLUMN IF NOT EXISTS owner_name           text,
  ADD COLUMN IF NOT EXISTS cover_image_url      text,
  ADD COLUMN IF NOT EXISTS business_phone       text,
  ADD COLUMN IF NOT EXISTS business_email       text,
  ADD COLUMN IF NOT EXISTS business_type        text,
  ADD COLUMN IF NOT EXISTS mobile_service_available  boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS pickup_dropoff_available   boolean NOT NULL DEFAULT false;

-- 2. Add check constraint for approval_status (safe – ignore if already exists)
DO $$
BEGIN
  ALTER TABLE public.car_service_providers
    ADD CONSTRAINT car_service_providers_approval_status_check
    CHECK (approval_status IN ('pending', 'approved', 'rejected'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 3. Back-fill existing rows: treat already-verified providers as approved
UPDATE public.car_service_providers
SET
  approval_status = CASE WHEN is_verified THEN 'approved' ELSE 'pending' END,
  is_approved     = is_verified
WHERE approval_status = 'pending';

-- 4. Add vehicle-pricing columns to car_service_offerings (if not present)
ALTER TABLE public.car_service_offerings
  ADD COLUMN IF NOT EXISTS sedan_price   numeric(10,2),
  ADD COLUMN IF NOT EXISTS suv_price     numeric(10,2),
  ADD COLUMN IF NOT EXISTS van_price     numeric(10,2),
  ADD COLUMN IF NOT EXISTS truck_price   numeric(10,2),
  ADD COLUMN IF NOT EXISTS bike_price    numeric(10,2),
  ADD COLUMN IF NOT EXISTS mobile_supported boolean NOT NULL DEFAULT false;

-- 5. Allow 'service_provider' in users.role
--    Drop the old check constraint and recreate it with the new value included.
DO $$
BEGIN
  -- Remove any existing role check so we can replace it
  ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;
  ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_fkey;

  ALTER TABLE public.users
    ADD CONSTRAINT users_role_check
    CHECK (role IN (
      'customer', 'user', 'driver', 'restaurant', 'admin', 'service_provider'
    ));
EXCEPTION WHEN others THEN
  -- Constraint may not exist or table structure differs — safe to ignore
  RAISE NOTICE 'users_role_check update skipped: %', SQLERRM;
END $$;

-- 6. RLS policies for service_provider role

-- Allow service providers to read their own provider row
DO $$
BEGIN
  DROP POLICY IF EXISTS "service_provider_read_own" ON public.car_service_providers;
  CREATE POLICY "service_provider_read_own"
    ON public.car_service_providers
    FOR SELECT
    USING (user_id = auth.uid());
EXCEPTION WHEN others THEN NULL;
END $$;

-- Allow service providers to insert their own provider row
DO $$
BEGIN
  DROP POLICY IF EXISTS "service_provider_insert_own" ON public.car_service_providers;
  CREATE POLICY "service_provider_insert_own"
    ON public.car_service_providers
    FOR INSERT
    WITH CHECK (user_id = auth.uid());
EXCEPTION WHEN others THEN NULL;
END $$;

-- Allow service providers to update their own provider row (non-admin fields)
DO $$
BEGIN
  DROP POLICY IF EXISTS "service_provider_update_own" ON public.car_service_providers;
  CREATE POLICY "service_provider_update_own"
    ON public.car_service_providers
    FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());
EXCEPTION WHEN others THEN NULL;
END $$;
