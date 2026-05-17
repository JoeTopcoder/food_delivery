-- Fix admin_verify_driver: also sets driver_status, is_food_driver_approved,
-- is_available_for_food, and approves/rejects all individual document rows.

CREATE OR REPLACE FUNCTION public.admin_verify_driver(
  p_driver_id UUID,
  p_is_verified BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_new_status TEXT;
  v_doc_status TEXT;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
  ) THEN
    RAISE EXCEPTION 'Unauthorized: admin only';
  END IF;

  v_new_status := CASE WHEN p_is_verified THEN 'approved' ELSE 'rejected' END;
  v_doc_status := CASE WHEN p_is_verified THEN 'approved' ELSE 'rejected' END;

  -- Update the main drivers row
  UPDATE public.drivers
  SET
    is_verified              = p_is_verified,
    driver_status            = v_new_status,
    documents_status         = v_doc_status,
    is_food_driver_approved  = p_is_verified,
    is_ride_driver_approved  = p_is_verified,
    is_available_for_food    = p_is_verified,
    is_available_for_rides   = p_is_verified,
    approved_at              = CASE WHEN p_is_verified THEN NOW() ELSE NULL END,
    rejection_reason         = CASE WHEN p_is_verified THEN NULL ELSE 'Application rejected by admin.' END,
    reviewed_at              = NOW(),
    updated_at               = NOW()
  WHERE id = p_driver_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Driver not found';
  END IF;

  -- Approve / reject all identity documents
  UPDATE public.driver_identity_documents
  SET verification_status = v_doc_status, updated_at = NOW()
  WHERE driver_id = p_driver_id;

  -- Approve / reject driver licence
  UPDATE public.driver_licenses
  SET verification_status = v_doc_status, updated_at = NOW()
  WHERE driver_id = p_driver_id;

  -- Approve / reject vehicle records
  UPDATE public.driver_vehicles
  SET verification_status = v_doc_status, updated_at = NOW()
  WHERE driver_id = p_driver_id;

  -- Approve / reject insurance records
  UPDATE public.driver_insurance
  SET verification_status = v_doc_status, updated_at = NOW()
  WHERE driver_id = p_driver_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.admin_verify_driver(UUID, BOOLEAN) TO authenticated;
