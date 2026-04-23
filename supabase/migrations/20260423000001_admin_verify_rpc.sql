-- Admin verify/reject RPC functions with SECURITY DEFINER
-- These bypass RLS and check admin role internally.

-- Verify or reject a driver
CREATE OR REPLACE FUNCTION public.admin_verify_driver(
  p_driver_id UUID,
  p_is_verified BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Ensure caller is admin
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Unauthorized: admin only';
  END IF;

  UPDATE public.drivers
  SET is_verified = p_is_verified, updated_at = NOW()
  WHERE id = p_driver_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Driver not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_verify_driver(UUID, BOOLEAN) TO authenticated;

-- Verify or reject a restaurant
CREATE OR REPLACE FUNCTION public.admin_verify_restaurant(
  p_restaurant_id UUID,
  p_is_verified BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Ensure caller is admin
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Unauthorized: admin only';
  END IF;

  UPDATE public.restaurants
  SET is_verified = p_is_verified, updated_at = NOW()
  WHERE id = p_restaurant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Restaurant not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_verify_restaurant(UUID, BOOLEAN) TO authenticated;
