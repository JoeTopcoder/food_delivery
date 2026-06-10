-- =============================================================================
-- Fix: Rides RLS policies blocked customers with role='customer'
-- Also adds: missing customer rating policy, missing driver DELETE on stale
-- driver_requests.
--
-- Root cause: migration 20260511000002 checked role = 'user', but migration
-- 20260503000001 changed the new-user trigger to write role = 'customer'.
-- Any customer registered after that migration could not create rides.
--
-- Also missing: no UPDATE policy allowed customers to submit a rating/review
-- after ride completion — any rating attempt silently failed (RLS blocked it).
-- =============================================================================

-- ─── 1. INSERT — allow both 'user' and 'customer' roles to book rides ─────────
DROP POLICY IF EXISTS "Customers create ride requests" ON public.ride_requests;

CREATE POLICY "Customers create ride requests"
  ON public.ride_requests
  FOR INSERT
  WITH CHECK (
    auth.uid() = customer_id
    AND (SELECT role FROM public.users WHERE id = auth.uid()) IN ('user', 'customer')
  );

-- ─── 2. UPDATE (cancel) — restore original without breaking role guard ─────────
-- The original policy had no role check on cancel; we keep it simple.
-- The INSERT policy's role guard already prevents wrong roles from creating rides.
DROP POLICY IF EXISTS "Customers cancel own rides" ON public.ride_requests;

CREATE POLICY "Customers cancel own rides"
  ON public.ride_requests
  FOR UPDATE
  USING (
    auth.uid() = customer_id
    AND ride_status NOT IN ('ride_started', 'ride_completed', 'cancelled')
  )
  WITH CHECK (
    auth.uid() = customer_id
    AND ride_status IN ('cancelled')
  );

-- ─── 3. UPDATE (rate) — customer submits rating + review after completion ──────
-- The 'rating' and 'review' columns on ride_requests are only meaningful
-- on completed rides.  Without this policy, any client-side rating update
-- is silently blocked by RLS and the customer never sees an error.
DROP POLICY IF EXISTS "Customers rate completed rides" ON public.ride_requests;

CREATE POLICY "Customers rate completed rides"
  ON public.ride_requests
  FOR UPDATE
  USING (
    auth.uid() = customer_id
    AND ride_status = 'ride_completed'
  )
  WITH CHECK (
    auth.uid() = customer_id
    AND ride_status = 'ride_completed'
  );

-- ─── 4. Driver: DELETE stale driver_requests (offered, then expired) ──────────
-- Edge functions clean up via service_role, but if the Flutter client ever
-- deletes an expired/rejected request record, it needs this policy.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'ride_driver_requests'
      AND policyname = 'Drivers delete own requests'
  ) THEN
    CREATE POLICY "Drivers delete own requests"
      ON public.ride_driver_requests
      FOR DELETE
      USING (
        EXISTS (
          SELECT 1 FROM public.drivers
          WHERE drivers.user_id = auth.uid()
            AND drivers.id = ride_driver_requests.driver_id
        )
      );
  END IF;
END $$;

-- ─── 5. INSERT missing for ride_driver_requests (driver self-offers) ──────────
-- When a driver proactively offers a ride via the Flutter client (not via Edge
-- Function), the INSERT needs an RLS policy.  Edge-function flows use
-- service_role and bypass this, but adding the policy is defence-in-depth.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'ride_driver_requests'
      AND policyname = 'Drivers insert own requests'
  ) THEN
    CREATE POLICY "Drivers insert own requests"
      ON public.ride_driver_requests
      FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.drivers
          WHERE drivers.user_id = auth.uid()
            AND drivers.id = ride_driver_requests.driver_id
        )
      );
  END IF;
END $$;

-- ─── 6. UPDATE ride_locations — drivers can update their own location ──────────
-- The original policy only had INSERT for drivers on ride_locations.
-- If the driver app updates an existing location row instead of inserting a new
-- one, this policy prevents an RLS block.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'ride_locations'
      AND policyname = 'Drivers update own location'
  ) THEN
    CREATE POLICY "Drivers update own location"
      ON public.ride_locations
      FOR UPDATE
      USING (
        EXISTS (
          SELECT 1 FROM public.drivers
          WHERE drivers.user_id = auth.uid()
            AND drivers.id = ride_locations.driver_id
        )
      )
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.drivers
          WHERE drivers.user_id = auth.uid()
            AND drivers.id = ride_locations.driver_id
        )
      );
  END IF;
END $$;
