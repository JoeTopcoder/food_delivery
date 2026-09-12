-- Clearer barcode-assign conflict message.
--
-- Barcodes are unique PER STORE (menus_store_barcode_uniq on
-- (restaurant_id, barcode)) — the same code is fine in different supermarkets.
-- The only in-store conflict is when another product in the SAME store already
-- carries the code. Name that product so staff know exactly what's wrong,
-- instead of a vague "already linked to another product in this store".
CREATE OR REPLACE FUNCTION public.assign_barcode(
  p_product_id UUID,
  p_barcode    TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_store    UUID;
  v_code     TEXT := NULLIF(btrim(p_barcode), '');
  v_conflict TEXT;
BEGIN
  IF v_code IS NULL THEN RAISE EXCEPTION 'Empty barcode'; END IF;
  SELECT restaurant_id INTO v_store FROM public.menus WHERE id = p_product_id;
  IF v_store IS NULL THEN RAISE EXCEPTION 'Product not found'; END IF;
  IF NOT (public.current_user_owns_restaurant(v_store) OR public.current_user_is_admin()) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;

  -- Same code on a DIFFERENT product in the SAME store → clear, named error.
  SELECT name INTO v_conflict
  FROM public.menus
  WHERE restaurant_id = v_store
    AND product_type = 'grocery'
    AND barcode = v_code
    AND id <> p_product_id
  LIMIT 1;
  IF v_conflict IS NOT NULL THEN
    RAISE EXCEPTION 'This QR code is already on "%".', v_conflict
      USING errcode = 'unique_violation';
  END IF;

  BEGIN
    UPDATE public.menus SET barcode = v_code, updated_at = now()
     WHERE id = p_product_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'This QR code is already on another product in this store.'
      USING errcode = 'unique_violation';
  END;
END;
$fn$;

NOTIFY pgrst, 'reload schema';
