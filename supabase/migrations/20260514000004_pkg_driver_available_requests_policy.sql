-- Allow drivers to see unassigned package requests so they can accept them.
-- Without this, the driver_select policy only shows rows where driver_id = their own id,
-- making searching_driver (driver_id = NULL) rows invisible to drivers.
CREATE POLICY "pkg_del_req_driver_select_available"
  ON public.package_delivery_requests FOR SELECT
  TO authenticated
  USING (delivery_status = 'searching_driver');
