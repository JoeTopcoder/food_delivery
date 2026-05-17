-- ====================================================================
-- RIDES MODULE - ROW LEVEL SECURITY POLICIES
-- Purpose: Secure access control for rides tables
-- ====================================================================

-- ====================================================================
-- RIDE_REQUESTS RLS POLICIES
-- ====================================================================

-- Customers can view only their own rides
CREATE POLICY "Customers view own rides" ON public.ride_requests
  FOR SELECT USING (
    auth.uid() = customer_id 
    OR EXISTS (
      SELECT 1 FROM public.drivers 
      WHERE drivers.user_id = auth.uid() 
      AND drivers.id = ride_requests.driver_id
    )
    OR (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- Customers can create ride requests for themselves
CREATE POLICY "Customers create ride requests" ON public.ride_requests
  FOR INSERT WITH CHECK (
    auth.uid() = customer_id
    AND (SELECT role FROM public.users WHERE id = auth.uid()) = 'user'
  );

-- Customers can cancel their own rides (before ride_started)
CREATE POLICY "Customers cancel own rides" ON public.ride_requests
  FOR UPDATE USING (
    auth.uid() = customer_id
    AND ride_status NOT IN ('ride_started', 'ride_completed', 'cancelled')
  )
  WITH CHECK (
    auth.uid() = customer_id
    AND ride_status IN ('cancelled')
  );

-- Drivers can view assigned rides
CREATE POLICY "Drivers view assigned rides" ON public.ride_requests
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.drivers 
      WHERE drivers.user_id = auth.uid() 
      AND drivers.id = ride_requests.driver_id
    )
  );

-- Drivers can update ride status for assigned rides
CREATE POLICY "Drivers update assigned rides" ON public.ride_requests
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.drivers 
      WHERE drivers.user_id = auth.uid() 
      AND drivers.id = ride_requests.driver_id
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.drivers 
      WHERE drivers.user_id = auth.uid() 
      AND drivers.id = ride_requests.driver_id
    )
  );

-- Admins can view all rides
CREATE POLICY "Admins view all rides" ON public.ride_requests
  FOR SELECT USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- Admins can update all rides
CREATE POLICY "Admins update all rides" ON public.ride_requests
  FOR UPDATE USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- ====================================================================
-- RIDE_DRIVER_REQUESTS RLS POLICIES
-- ====================================================================

-- Drivers can view requests sent to them
CREATE POLICY "Drivers view own requests" ON public.ride_driver_requests
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.drivers 
      WHERE drivers.user_id = auth.uid() 
      AND drivers.id = ride_driver_requests.driver_id
    )
  );

-- Drivers can update their responses
CREATE POLICY "Drivers respond to requests" ON public.ride_driver_requests
  FOR UPDATE USING (
    EXISTS (
      SELECT 1 FROM public.drivers 
      WHERE drivers.user_id = auth.uid() 
      AND drivers.id = ride_driver_requests.driver_id
    )
  );

-- Customers can view requests for their rides
CREATE POLICY "Customers view ride requests" ON public.ride_driver_requests
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.ride_requests
      WHERE ride_requests.id = ride_driver_requests.ride_id
      AND ride_requests.customer_id = auth.uid()
    )
  );

-- Admins can view all requests
CREATE POLICY "Admins view all requests" ON public.ride_driver_requests
  FOR SELECT USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- ====================================================================
-- RIDE_LOCATIONS RLS POLICIES
-- ====================================================================

-- Drivers can insert their own location
CREATE POLICY "Drivers insert own location" ON public.ride_locations
  FOR INSERT WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.drivers 
      WHERE drivers.user_id = auth.uid() 
      AND drivers.id = ride_locations.driver_id
    )
  );

-- Customers can view driver location for their active rides
CREATE POLICY "Customers view ride locations" ON public.ride_locations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.ride_requests
      WHERE ride_requests.id = ride_locations.ride_id
      AND ride_requests.customer_id = auth.uid()
    )
  );

-- Drivers can view their own locations
CREATE POLICY "Drivers view own locations" ON public.ride_locations
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.drivers 
      WHERE drivers.user_id = auth.uid() 
      AND drivers.id = ride_locations.driver_id
    )
  );

-- Admins can view all locations
CREATE POLICY "Admins view all locations" ON public.ride_locations
  FOR SELECT USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- ====================================================================
-- RIDE_MESSAGES RLS POLICIES
-- ====================================================================

-- Participants can view messages in their rides
CREATE POLICY "Participants view ride messages" ON public.ride_messages
  FOR SELECT USING (
    auth.uid() = sender_id 
    OR auth.uid() = receiver_id
  );

-- Participants can send messages
CREATE POLICY "Participants send ride messages" ON public.ride_messages
  FOR INSERT WITH CHECK (
    auth.uid() = sender_id
  );

-- Receivers can mark messages as read
CREATE POLICY "Receivers mark messages read" ON public.ride_messages
  FOR UPDATE USING (
    auth.uid() = receiver_id
  )
  WITH CHECK (
    auth.uid() = receiver_id
  );

-- Admins can view all messages
CREATE POLICY "Admins view all messages" ON public.ride_messages
  FOR SELECT USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- ====================================================================
-- RIDE_PRICING_SETTINGS RLS POLICIES
-- ====================================================================

-- Everyone can view pricing settings
CREATE POLICY "Public view pricing settings" ON public.ride_pricing_settings
  FOR SELECT USING (TRUE);

-- Only admins can update pricing settings
CREATE POLICY "Admins update pricing settings" ON public.ride_pricing_settings
  FOR UPDATE USING (
    (SELECT role FROM public.users WHERE id = auth.uid()) = 'admin'
  );

-- ====================================================================
-- ENABLE RLS ON ALL TABLES
-- ====================================================================
ALTER TABLE public.ride_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ride_driver_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ride_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ride_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ride_pricing_settings ENABLE ROW LEVEL SECURITY;

-- ====================================================================
-- COMPLETE - RLS policies applied
-- ====================================================================
