-- Migration: place a school lunch order
--
-- Implements the "client is never trusted" rule literally. The app sends item
-- ids, quantities and an optional student. Everything with money or permission
-- attached is derived here:
--   parent from auth.uid(), the student link re-checked, the school address
--   read from the school record, prices from the menu, the delivery fee from
--   the recipient, the total from those. A submitted price or fee is ignored
--   entirely rather than validated, because there is no reason to accept one.

CREATE OR REPLACE FUNCTION public.place_lunch_order(
  p_items        JSONB,           -- [{item_id, qty}]
  p_student_id   UUID DEFAULT NULL,
  p_instructions TEXT DEFAULT NULL,
  p_payment_method TEXT DEFAULT 'wallet'
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_parent     UUID := auth.uid();
  v_is_student BOOLEAN := p_student_id IS NOT NULL;
  v_subtotal   NUMERIC := 0;
  v_fee        NUMERIC;
  v_total      NUMERIC;
  -- Scalars, not a RECORD: see quote_lunch_order — an unassigned RECORD
  -- cannot be read, which broke every self order.
  v_school_id      UUID;
  v_school_name    TEXT;
  v_school_address TEXT;
  v_restaurant UUID;
  v_order_id   UUID := gen_random_uuid();
  v_addr       TEXT;
  v_item_count INT;
BEGIN
  IF v_parent IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;
  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'No items in the order';
  END IF;

  -- Student authorisation, re-checked in the database rather than trusted.
  IF v_is_student AND NOT EXISTS (
    SELECT 1 FROM public.parent_student_links
    WHERE parent_id = v_parent AND student_id = p_student_id AND status = 'active'
  ) THEN
    RAISE EXCEPTION 'You are not authorized to order lunch for this student';
  END IF;

  -- Prices and availability from the menu. Unavailable items are rejected
  -- rather than silently dropped: a parent must not discover at the school
  -- gate that half the order was quietly removed.
  -- Postgres has no min(uuid), so the provider is taken from any matched row
  -- rather than aggregated. All lunch items in one order come from one
  -- provider; a mixed cart is rejected below by the count check.
  SELECT COUNT(*), COALESCE(SUM(m.price * i.qty), 0)
    INTO v_item_count, v_subtotal
  FROM jsonb_to_recordset(p_items) AS i(item_id UUID, qty INT)
  JOIN public.menus m ON m.id = i.item_id
  WHERE m.is_available;

  SELECT m.restaurant_id INTO v_restaurant
  FROM jsonb_to_recordset(p_items) AS i(item_id UUID, qty INT)
  JOIN public.menus m ON m.id = i.item_id
  WHERE m.is_available
  LIMIT 1;

  IF v_item_count <> jsonb_array_length(p_items) THEN
    RAISE EXCEPTION 'Some items are no longer available. Please review your cart.';
  END IF;

  v_fee := CASE WHEN v_is_student
    THEN COALESCE((SELECT value FROM app_config WHERE key='lunch_delivery_fee_student')::NUMERIC, 350)
    ELSE COALESCE((SELECT value FROM app_config WHERE key='lunch_delivery_fee_self')::NUMERIC, 900)
  END;
  v_total := ROUND(v_subtotal + v_fee, 2);

  IF v_is_student THEN
    SELECT s.id, s.name, s.address INTO v_school_id, v_school_name, v_school_address
    FROM public.student_profiles sp
    JOIN public.schools s ON s.id = sp.school_id
    WHERE sp.user_id = p_student_id;

    IF v_school_id IS NULL THEN
      RAISE EXCEPTION 'That student has no school on file, so lunch cannot be delivered to them.';
    END IF;
    v_addr := v_school_address;
  ELSE
    -- Ordering for yourself goes to your own default address.
    SELECT a.address INTO v_addr
    FROM public.user_addresses a
    WHERE a.user_id = v_parent
    ORDER BY a.is_default DESC
    LIMIT 1;
  END IF;

  INSERT INTO public.orders (
    id, user_id, restaurant_id, subtotal, delivery_fee, total_amount,
    status, payment_method, payment_status, ordered_at,
    delivery_address, special_instructions,
    recipient_type, student_id, school_id, school_name, school_address
  ) VALUES (
    v_order_id, v_parent, v_restaurant, v_subtotal, v_fee, v_total,
    'pending', p_payment_method, 'pending', now(),
    v_addr, p_instructions,
    CASE WHEN v_is_student THEN 'student' ELSE 'self' END,
    p_student_id, v_school_id, v_school_name, v_school_address
  );

  INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, subtotal)
  SELECT v_order_id, m.id, m.name, m.price, i.qty, m.price * i.qty
  FROM jsonb_to_recordset(p_items) AS i(item_id UUID, qty INT)
  JOIN public.menus m ON m.id = i.item_id;

  RETURN jsonb_build_object(
    'order_id',       v_order_id,
    'recipient_type', CASE WHEN v_is_student THEN 'student' ELSE 'self' END,
    'subtotal',       ROUND(v_subtotal, 2),
    'delivery_fee',   ROUND(v_fee, 2),
    'total',          v_total,
    'school_name',    v_school_name,
    'school_address', v_school_address
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.place_lunch_order TO authenticated;

NOTIFY pgrst, 'reload schema';
