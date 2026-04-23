-- Update admin_verify_driver: set documents_status = 'rejected'/'approved' accordingly
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
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Unauthorized: admin only';
  END IF;

  UPDATE public.drivers
  SET
    is_verified    = p_is_verified,
    documents_status = CASE WHEN p_is_verified THEN 'approved' ELSE 'rejected' END,
    updated_at     = NOW()
  WHERE id = p_driver_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Driver not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_verify_driver(UUID, BOOLEAN) TO authenticated;

-- Update admin_verify_restaurant: repurpose status field:
--   'active'   = verified (live on app)
--   'rejected' = admin rejected
--   'draft'    = pending review
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
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Unauthorized: admin only';
  END IF;

  UPDATE public.restaurants
  SET
    is_verified = p_is_verified,
    status      = CASE WHEN p_is_verified THEN 'active' ELSE 'rejected' END,
    updated_at  = NOW()
  WHERE id = p_restaurant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Restaurant not found';
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_verify_restaurant(UUID, BOOLEAN) TO authenticated;
