-- ============================================================
-- Fix infinite RLS recursion on ride_requests / ride_driver_requests
--
-- Cycle:
--   ride_requests SELECT policy "Drivers view rides with pending request"
--     → queries ride_driver_requests
--   ride_driver_requests SELECT policy "Customers view ride requests"
--     → queries ride_requests   ← LOOP
--
-- Fix: replace the ride_driver_requests customer policy with a
-- SECURITY DEFINER helper that bypasses RLS when looking up the
-- ride's customer_id, breaking the cycle.
-- ============================================================

-- 1. Helper: returns customer_id for a ride without triggering RLS
CREATE OR REPLACE FUNCTION public.ride_customer_id(p_ride_id UUID)
RETURNS UUID LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT customer_id FROM public.ride_requests WHERE id = p_ride_id;
$$;
GRANT EXECUTE ON FUNCTION public.ride_customer_id(UUID) TO authenticated;

-- 2. Drop the recursive policy and recreate via the helper
DROP POLICY IF EXISTS "Customers view ride requests" ON public.ride_driver_requests;

CREATE POLICY "Customers view ride requests" ON public.ride_driver_requests
  FOR SELECT USING (
    public.ride_customer_id(ride_id) = auth.uid()
  );
