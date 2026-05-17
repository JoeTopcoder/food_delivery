-- =============================================================================
-- RLS Policies: Package Delivery Module
-- =============================================================================

-- Enable RLS on all new tables
ALTER TABLE public.shipping_companies          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_records             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_delivery_requests   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_scans               ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_delivery_locations  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.shipping_company_webhooks   ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------------------------
-- Helper: is current user an admin?
-- Using SECURITY DEFINER to avoid RLS recursion on the users table.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.pkg_is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
  );
$$;

-- Helper: get driver id for current user
CREATE OR REPLACE FUNCTION public.pkg_my_driver_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1;
$$;

-- ============================================================================
-- shipping_companies
-- ============================================================================

-- All authenticated users can view active companies
CREATE POLICY "pkg_companies_select_active"
  ON public.shipping_companies FOR SELECT
  TO authenticated
  USING (active = true OR public.pkg_is_admin());

-- Admins can manage companies
CREATE POLICY "pkg_companies_admin_all"
  ON public.shipping_companies FOR ALL
  TO authenticated
  USING (public.pkg_is_admin())
  WITH CHECK (public.pkg_is_admin());

-- Service role full access (edge functions)
CREATE POLICY "pkg_companies_service_role"
  ON public.shipping_companies FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- package_records
-- ============================================================================

-- Customers can see packages associated with their account
CREATE POLICY "pkg_records_customer_select"
  ON public.package_records FOR SELECT
  TO authenticated
  USING (customer_id = auth.uid() OR public.pkg_is_admin());

-- Drivers can see records for their assigned deliveries
CREATE POLICY "pkg_records_driver_select"
  ON public.package_records FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.package_delivery_requests pdr
      WHERE pdr.package_record_id = package_records.id
        AND pdr.driver_id = public.pkg_my_driver_id()
    )
  );

-- Service role full access
CREATE POLICY "pkg_records_service_role"
  ON public.package_records FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- package_delivery_requests
-- ============================================================================

-- Customers see their own requests
CREATE POLICY "pkg_del_req_customer_select"
  ON public.package_delivery_requests FOR SELECT
  TO authenticated
  USING (customer_id = auth.uid() OR public.pkg_is_admin());

-- Customers can insert (via service, but also directly)
CREATE POLICY "pkg_del_req_customer_insert"
  ON public.package_delivery_requests FOR INSERT
  TO authenticated
  WITH CHECK (customer_id = auth.uid());

-- Drivers see assigned deliveries
CREATE POLICY "pkg_del_req_driver_select"
  ON public.package_delivery_requests FOR SELECT
  TO authenticated
  USING (driver_id = public.pkg_my_driver_id());

-- Drivers can update status of their assigned deliveries
CREATE POLICY "pkg_del_req_driver_update"
  ON public.package_delivery_requests FOR UPDATE
  TO authenticated
  USING (driver_id = public.pkg_my_driver_id())
  WITH CHECK (driver_id = public.pkg_my_driver_id());

-- Service role full access (edge functions handle all mutations)
CREATE POLICY "pkg_del_req_service_role"
  ON public.package_delivery_requests FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- package_scans
-- ============================================================================

-- Drivers can insert scans
CREATE POLICY "pkg_scans_driver_insert"
  ON public.package_scans FOR INSERT
  TO authenticated
  WITH CHECK (driver_id = public.pkg_my_driver_id());

-- Drivers can see their own scans
CREATE POLICY "pkg_scans_driver_select"
  ON public.package_scans FOR SELECT
  TO authenticated
  USING (driver_id = public.pkg_my_driver_id() OR public.pkg_is_admin());

-- Service role full access
CREATE POLICY "pkg_scans_service_role"
  ON public.package_scans FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- package_delivery_locations
-- ============================================================================

-- Drivers insert their location
CREATE POLICY "pkg_locations_driver_insert"
  ON public.package_delivery_locations FOR INSERT
  TO authenticated
  WITH CHECK (driver_id = public.pkg_my_driver_id());

-- Customers can see driver location for their active deliveries
CREATE POLICY "pkg_locations_customer_select"
  ON public.package_delivery_locations FOR SELECT
  TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.package_delivery_requests pdr
      WHERE pdr.id = delivery_request_id
        AND (pdr.customer_id = auth.uid() OR public.pkg_is_admin())
    )
  );

-- Service role full access
CREATE POLICY "pkg_locations_service_role"
  ON public.package_delivery_locations FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- shipping_company_webhooks
-- ============================================================================

-- Admins see all webhooks
CREATE POLICY "pkg_webhooks_admin"
  ON public.shipping_company_webhooks FOR ALL
  TO authenticated
  USING (public.pkg_is_admin())
  WITH CHECK (public.pkg_is_admin());

-- Service role full access
CREATE POLICY "pkg_webhooks_service_role"
  ON public.shipping_company_webhooks FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);
