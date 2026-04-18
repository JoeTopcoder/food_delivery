-- Allow drivers to UPDATE their own declined orders (needed for upsert on re-decline)
CREATE POLICY "drivers_update_own_declines"
  ON public.driver_declined_orders FOR UPDATE
  USING (
    driver_id IN (
      SELECT id FROM public.drivers WHERE user_id = auth.uid()
    )
  )
  WITH CHECK (
    driver_id IN (
      SELECT id FROM public.drivers WHERE user_id = auth.uid()
    )
  );
