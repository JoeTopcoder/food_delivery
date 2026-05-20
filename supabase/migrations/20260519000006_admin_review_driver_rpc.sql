-- Admin review driver application — direct SQL RPC
-- Replaces the edge-function call for approve/reject to avoid JWT and
-- JSONB cast issues. SECURITY DEFINER so it runs as owner (bypasses
-- the drivers UPDATE RLS) after verifying the caller is_admin().

CREATE OR REPLACE FUNCTION public.admin_review_driver_application(
  p_driver_id            UUID,
  p_approved             BOOLEAN,
  p_approve_food_delivery BOOLEAN DEFAULT FALSE,
  p_approve_ride_sharing  BOOLEAN DEFAULT FALSE,
  p_rejection_reason     TEXT    DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id  UUID        := auth.uid();
  v_old_status TEXT;
  v_new_status TEXT;
  v_now        TIMESTAMPTZ := NOW();
BEGIN
  -- Verify caller is admin
  IF NOT is_admin() THEN
    RAISE EXCEPTION 'Forbidden: admin access required';
  END IF;

  -- Fetch current status for the log
  SELECT driver_status INTO v_old_status
  FROM public.drivers
  WHERE id = p_driver_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Driver not found';
  END IF;

  v_new_status := CASE WHEN p_approved THEN 'approved' ELSE 'rejected' END;

  -- Update the driver row
  UPDATE public.drivers SET
    driver_status           = v_new_status,
    reviewed_by             = v_admin_id,
    reviewed_at             = v_now,
    updated_at              = v_now,
    approved_at             = CASE WHEN p_approved THEN v_now ELSE approved_at END,
    is_food_driver_approved = CASE WHEN p_approved THEN p_approve_food_delivery ELSE FALSE END,
    is_ride_driver_approved = CASE WHEN p_approved THEN p_approve_ride_sharing  ELSE FALSE END,
    is_available_for_food   = CASE WHEN p_approved THEN p_approve_food_delivery ELSE FALSE END,
    is_available_for_rides  = CASE WHEN p_approved THEN p_approve_ride_sharing  ELSE FALSE END,
    is_online               = CASE WHEN p_approved THEN is_online               ELSE FALSE END,
    is_verified             = p_approved,
    -- documents_status is JSONB — use to_jsonb() to avoid cast errors
    documents_status        = to_jsonb(v_new_status::text),
    rejection_reason        = CASE
                                WHEN p_approved THEN NULL
                                ELSE COALESCE(p_rejection_reason, 'Application rejected by admin.')
                              END
  WHERE id = p_driver_id;

  -- Audit log
  INSERT INTO public.driver_verification_logs
    (driver_id, action, actor_id, old_status, new_status, notes)
  VALUES (
    p_driver_id,
    CASE WHEN p_approved THEN 'application_approved' ELSE 'application_rejected' END,
    v_admin_id,
    v_old_status,
    v_new_status,
    CASE WHEN p_approved
      THEN format('Approved: food=%s, rides=%s', p_approve_food_delivery, p_approve_ride_sharing)
      ELSE format('Rejected: %s', COALESCE(p_rejection_reason, 'no reason given'))
    END
  );

  RETURN jsonb_build_object(
    'success',                true,
    'driver_id',              p_driver_id,
    'driver_status',          v_new_status,
    'is_food_driver_approved', CASE WHEN p_approved THEN p_approve_food_delivery ELSE FALSE END,
    'is_ride_driver_approved', CASE WHEN p_approved THEN p_approve_ride_sharing  ELSE FALSE END
  );
END;
$$;

-- Grant execute to authenticated users (is_admin() check inside guards access)
GRANT EXECUTE ON FUNCTION public.admin_review_driver_application TO authenticated;
