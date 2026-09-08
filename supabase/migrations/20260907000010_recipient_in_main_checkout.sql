-- Migration: move "order for a student" out of a lunch vertical and into the
-- main checkout.
--
-- The separate lunch menu/cart/checkout is gone. A parent now shops the ordinary
-- restaurant and grocery menus with the ordinary cart, and chooses the recipient
-- at the ordinary checkout. What survives from the lunch build is the part worth
-- keeping: schools, student profiles, parent-student links, and linking by
-- wallet ID.
--
-- Consequently quote_lunch_order and place_lunch_order are dropped. They priced
-- and placed orders for one vertical that no longer exists, and leaving an
-- unused SECURITY DEFINER function that can create orders is a liability, not a
-- spare part.

-- ── School coordinates reach the client ────────────────────────────────────
-- The main checkout looks up zone tax by coordinate, so a delivery redirected
-- to a school needs the school's own position, not the parent's home.
DROP FUNCTION IF EXISTS public.get_my_students();

CREATE FUNCTION public.get_my_students()
RETURNS TABLE (
  student_id     UUID,
  student_name   TEXT,
  wallet_id      TEXT,
  school_id      UUID,
  school_name    TEXT,
  school_address TEXT,
  school_lat     DOUBLE PRECISION,
  school_lng     DOUBLE PRECISION
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u.id,
         u.name,
         UPPER(COALESCE(NULLIF(u.referral_code, ''),
                        LEFT(REPLACE(u.id::text, '-', ''), 6))),
         s.id, s.name, s.address, s.latitude, s.longitude
  FROM public.parent_student_links l
  JOIN public.users u ON u.id = l.student_id
  LEFT JOIN public.student_profiles sp ON sp.user_id = u.id
  LEFT JOIN public.schools s ON s.id = sp.school_id
  WHERE l.parent_id = auth.uid() AND l.status = 'active'
  ORDER BY u.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_students TO authenticated;

-- ── Unlinking ──────────────────────────────────────────────────────────────
-- Revoked rather than deleted, so past orders keep their explanation of who
-- authorised them.
CREATE OR REPLACE FUNCTION public.unlink_student(p_student_id UUID)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_parent UUID := auth.uid();
BEGIN
  IF v_parent IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  UPDATE public.parent_student_links
     SET status = 'revoked'
   WHERE parent_id = v_parent AND student_id = p_student_id;
  RETURN jsonb_build_object('unlinked', TRUE);
END;
$$;

GRANT EXECUTE ON FUNCTION public.unlink_student TO authenticated;

-- ── Authoritative student order pricing, for any vertical ──────────────────
-- Returns the school and the flat fee for an order a parent wants to send to a
-- student, or raises if they may not. Every checkout and every order-placing
-- edge function calls this rather than reimplementing the rule.
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

-- ── Fee config ─────────────────────────────────────────────────────────────
-- One flat rate for any order going to a school, whatever the vertical, and it
-- is now an ordinary app_config row the admin fee screen can edit.
INSERT INTO public.app_config (key, value, value_type, description)
VALUES ('student_delivery_fee', '350', 'number',
        'Flat delivery fee (JMD) for an order sent to a student at their school')
ON CONFLICT (key) DO UPDATE
  SET value_type = 'number',
      description = EXCLUDED.description;

DELETE FROM public.app_config
 WHERE key IN ('lunch_delivery_fee_self', 'lunch_delivery_fee_student');

-- ── Retire the lunch vertical ──────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.quote_lunch_order(JSONB, UUID);
DROP FUNCTION IF EXISTS public.place_lunch_order(JSONB, UUID, TEXT, TEXT);

-- The seeded lunch provider becomes an ordinary restaurant so its menu is
-- reachable from the normal food listing rather than orphaned behind a
-- store_type nothing browses any more.
UPDATE public.restaurants
   SET store_type = 'food'
 WHERE store_type = 'lunch';

UPDATE public.menus
   SET product_type = 'food'
 WHERE product_type = 'lunch';

NOTIFY pgrst, 'reload schema';
