-- Hold scheduled orders from drivers until close to their slot. A scheduled
-- order stays invisible to drivers until now() is within the prep+travel lead
-- window (75 min) of scheduled_for; then it surfaces for pickup like any order.
DROP POLICY IF EXISTS drivers_select_available_orders ON public.orders;
CREATE POLICY drivers_select_available_orders ON public.orders
  FOR SELECT
  TO authenticated
  USING (
    driver_id IS NULL
    AND status IN ('pending', 'confirmed', 'preparing', 'ready')
    AND (payment_method NOT IN ('stripe', 'card') OR payment_status = 'completed')
    AND (scheduled_for IS NULL OR scheduled_for <= now() + interval '75 minutes')
    AND EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = auth.uid())
  );

NOTIFY pgrst, 'reload schema';
