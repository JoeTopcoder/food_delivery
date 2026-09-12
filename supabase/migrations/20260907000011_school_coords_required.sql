-- Migration: a school delivery needs a locatable school.
--
-- resolve_student_delivery previously returned a school whether or not it had
-- coordinates. The callers only override the delivery position when one is
-- present, so a school with no lat/lng left the order carrying the PARENT's
-- coordinates under the school's address — the driver would have been routed to
-- the parent's house while the order said it was going to the school.
--
-- Refusing up front is the honest failure: you cannot dispatch a driver to a
-- place you cannot locate, and the parent finds out before paying rather than
-- after.

CREATE OR REPLACE FUNCTION public.resolve_student_delivery(
  p_parent_id  UUID,
  p_student_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_school_id      UUID;
  v_school_name    TEXT;
  v_school_address TEXT;
  v_lat            DOUBLE PRECISION;
  v_lng            DOUBLE PRECISION;
  v_fee            NUMERIC;
BEGIN
  IF p_parent_id IS NULL OR p_student_id IS NULL THEN
    RAISE EXCEPTION 'Both parent and student are required';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM public.parent_student_links
    WHERE parent_id = p_parent_id AND student_id = p_student_id
      AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'You are not authorized to order for this student';
  END IF;

  SELECT s.id, s.name, s.address, s.latitude, s.longitude
    INTO v_school_id, v_school_name, v_school_address, v_lat, v_lng
  FROM public.student_profiles sp
  JOIN public.schools s ON s.id = sp.school_id
  WHERE sp.user_id = p_student_id AND s.is_active;

  IF v_school_id IS NULL THEN
    RAISE EXCEPTION 'That student has no school on file, so the order cannot be delivered to them.';
  END IF;

  IF v_lat IS NULL OR v_lng IS NULL THEN
    RAISE EXCEPTION 'That school has no map location set yet, so a driver cannot be sent to it. Contact support.';
  END IF;

  v_fee := COALESCE(
    (SELECT value FROM public.app_config WHERE key = 'student_delivery_fee')::NUMERIC,
    350
  );

  RETURN jsonb_build_object(
    'student_id',     p_student_id,
    'school_id',      v_school_id,
    'school_name',    v_school_name,
    'school_address', v_school_address,
    'school_lat',     v_lat,
    'school_lng',     v_lng,
    'delivery_fee',   v_fee
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.resolve_student_delivery TO authenticated, service_role;

-- The seeded test school gets a location so the flow is exercisable. Its name
-- and address are placeholders from the original seed, not a real school.
UPDATE public.schools
   SET latitude = 18.0179, longitude = -76.8099
 WHERE latitude IS NULL AND name = 'ABC High School';

NOTIFY pgrst, 'reload schema';
