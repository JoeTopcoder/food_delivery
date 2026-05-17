-- Auto-expire rides stuck in 'requested' or 'searching_driver' for more than 15 minutes.
-- Called via RPC when the customer opens the app, so no pg_cron dependency needed.
CREATE OR REPLACE FUNCTION public.auto_expire_stale_rides(p_customer_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.ride_requests
  SET
    ride_status         = 'failed',
    cancellation_reason = 'No drivers available',
    updated_at          = NOW()
  WHERE
    customer_id = p_customer_id
    AND ride_status IN ('requested', 'searching_driver')
    AND updated_at < NOW() - INTERVAL '15 minutes';
END;
$$;

-- Allow any authenticated user to call it for their own rides (SECURITY DEFINER handles the write)
GRANT EXECUTE ON FUNCTION public.auto_expire_stale_rides(UUID) TO authenticated;
