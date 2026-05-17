-- Allow drivers to read ride details for rides where they have a pending or offered request.
-- Without this, RLS blocks the fetch because driver_id on ride_requests is NULL pre-assignment.
CREATE POLICY "Drivers view rides with pending request" ON public.ride_requests
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.ride_driver_requests rdr
      JOIN public.drivers d ON d.id = rdr.driver_id
      WHERE rdr.ride_id = ride_requests.id
        AND d.user_id = auth.uid()
        AND rdr.status IN ('pending', 'offered')
    )
  );
