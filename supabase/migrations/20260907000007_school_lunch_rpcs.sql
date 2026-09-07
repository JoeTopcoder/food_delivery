-- Migration: school lunch RPCs
--
-- Everything the client sends is a REQUEST, never authority. The parent is
-- taken from auth.uid(), the student link is re-checked in the database, the
-- school address is read from the school record, prices come from the menu and
-- the delivery fee is derived from the recipient — none of it is accepted from
-- the app.

-- ── Link a student by wallet ID ────────────────────────────────────────────
-- Resolves the wallet ID exactly as wallet_transfer does, so the code a parent
-- reads off their child's profile is the same code that works here.
CREATE OR REPLACE FUNCTION public.link_student_by_wallet_id(p_wallet_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_parent  UUID := auth.uid();
  v_student RECORD;
BEGIN
  IF v_parent IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  SELECT u.id, u.name, u.email INTO v_student
  FROM public.users u
  WHERE UPPER(COALESCE(u.referral_code, '')) = UPPER(TRIM(p_wallet_id))
     OR UPPER(LEFT(REPLACE(u.id::text, '-', ''), 6)) = UPPER(TRIM(p_wallet_id))
  LIMIT 1;

  IF v_student.id IS NULL THEN
    RAISE EXCEPTION 'No account found with that wallet ID';
  END IF;

  IF v_student.id = v_parent THEN
    RAISE EXCEPTION 'That is your own wallet ID';
  END IF;

  INSERT INTO public.parent_student_links (parent_id, student_id, status)
  VALUES (v_parent, v_student.id, 'active')
  ON CONFLICT (parent_id, student_id)
  DO UPDATE SET status = 'active';

  -- A student row is created on first link so the school can be set later.
  INSERT INTO public.student_profiles (user_id)
  VALUES (v_student.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN jsonb_build_object(
    'linked', TRUE,
    'student_id', v_student.id,
    'student_name', v_student.name,
    'wallet_id', UPPER(TRIM(p_wallet_id))
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.link_student_by_wallet_id TO authenticated;

-- ── Students this parent may order for ─────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_students()
RETURNS TABLE (
  student_id     UUID,
  student_name   TEXT,
  wallet_id      TEXT,
  school_id      UUID,
  school_name    TEXT,
  school_address TEXT
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT u.id,
         u.name,
         UPPER(COALESCE(NULLIF(u.referral_code, ''),
                        LEFT(REPLACE(u.id::text, '-', ''), 6))),
         s.id, s.name, s.address
  FROM public.parent_student_links l
  JOIN public.users u ON u.id = l.student_id
  LEFT JOIN public.student_profiles sp ON sp.user_id = u.id
  LEFT JOIN public.schools s ON s.id = sp.school_id
  WHERE l.parent_id = auth.uid() AND l.status = 'active'
  ORDER BY u.name;
$$;

GRANT EXECUTE ON FUNCTION public.get_my_students TO authenticated;

-- ── Authoritative lunch quote ──────────────────────────────────────────────
-- The checkout screen calls this whenever the recipient changes. It returns
-- what the order WOULD cost, computed the same way placing it will be, so the
-- figure on screen is never one the client made up.
CREATE OR REPLACE FUNCTION public.quote_lunch_order(
  p_items      JSONB,          -- [{item_id, qty}]
  p_student_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_parent   UUID := auth.uid();
  v_subtotal NUMERIC := 0;
  v_fee      NUMERIC;
  v_is_stu   BOOLEAN := p_student_id IS NOT NULL;
  -- Scalars, not a RECORD: an unassigned RECORD cannot be read, so a self
  -- order (which never looks up a school) threw "record not assigned yet".
  v_school_id      UUID;
  v_school_name    TEXT;
  v_school_address TEXT;
BEGIN
  IF v_parent IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF v_is_stu AND NOT EXISTS (
    SELECT 1 FROM public.parent_student_links
    WHERE parent_id = v_parent AND student_id = p_student_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'You are not authorized to order lunch for this student';
  END IF;

  -- Prices from the menu, never from the request.
  SELECT COALESCE(SUM(m.price * (i.qty)::INT), 0) INTO v_subtotal
  FROM jsonb_to_recordset(p_items) AS i(item_id UUID, qty INT)
  JOIN public.menus m ON m.id = i.item_id AND m.is_available;

  v_fee := CASE WHEN v_is_stu
    THEN COALESCE((SELECT value FROM app_config WHERE key='lunch_delivery_fee_student')::NUMERIC, 350)
    ELSE COALESCE((SELECT value FROM app_config WHERE key='lunch_delivery_fee_self')::NUMERIC, 900)
  END;

  IF v_is_stu THEN
    SELECT s.id, s.name, s.address INTO v_school_id, v_school_name, v_school_address
    FROM public.student_profiles sp
    JOIN public.schools s ON s.id = sp.school_id
    WHERE sp.user_id = p_student_id;
  END IF;

  RETURN jsonb_build_object(
    'recipient_type', CASE WHEN v_is_stu THEN 'student' ELSE 'self' END,
    'subtotal',       ROUND(v_subtotal, 2),
    'delivery_fee',   ROUND(v_fee, 2),
    'total',          ROUND(v_subtotal + v_fee, 2),
    'school_id',      v_school_id,
    'school_name',    v_school_name,
    'school_address', v_school_address
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.quote_lunch_order TO authenticated;

NOTIFY pgrst, 'reload schema';
