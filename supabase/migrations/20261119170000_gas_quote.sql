-- Cooking Gas — price quote (no side effects) for the pre-placement summary.
-- Mirrors place_gas_order's math so the UI can show Delivery/Service/Total
-- before the order is created. Returns in_zone=false when outside coverage.
CREATE OR REPLACE FUNCTION public.gas_quote(
  p_supplier uuid, p_items jsonb, p_lat double precision, p_lng double precision
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_svc bigint; v_zone bigint; v_item jsonb; v_prod public.gas_products%ROWTYPE;
  v_qty int; v_ptype text; v_unit bigint; v_items bigint := 0; v_dep bigint := 0; v_in_zone boolean := false;
BEGIN
  SELECT service_fee_cents INTO v_svc FROM public.gas_settings WHERE id = 1;
  SELECT delivery_fee_cents INTO v_zone FROM public.gas_delivery_zones z
   WHERE z.supplier_id = p_supplier AND z.is_active = true
     AND p_lat IS NOT NULL AND p_lng IS NOT NULL
     AND (6371 * acos(greatest(-1, least(1,
           cos(radians(z.center_lat))*cos(radians(p_lat))*cos(radians(p_lng)-radians(z.center_lng))
           + sin(radians(z.center_lat))*sin(radians(p_lat)))))) <= z.radius_km
   ORDER BY z.delivery_fee_cents ASC LIMIT 1;
  v_in_zone := v_zone IS NOT NULL;

  IF p_items IS NOT NULL AND jsonb_typeof(p_items) = 'array' THEN
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
      v_ptype := v_item->>'purchase_type';
      v_qty := COALESCE((v_item->>'qty')::int, 0);
      SELECT * INTO v_prod FROM public.gas_products
        WHERE id = (v_item->>'product_id')::uuid AND supplier_id = p_supplier;
      IF FOUND AND v_qty > 0 THEN
        v_unit := CASE WHEN v_ptype='exchange' THEN v_prod.exchange_price_cents ELSE v_prod.new_price_cents END;
        v_items := v_items + COALESCE(v_unit,0) * v_qty;
        IF v_ptype='new' THEN v_dep := v_dep + v_prod.deposit_cents * v_qty; END IF;
      END IF;
    END LOOP;
  END IF;

  RETURN jsonb_build_object(
    'items_cents', v_items, 'deposit_cents', v_dep,
    'delivery_cents', COALESCE(v_zone,0), 'service_fee_cents', COALESCE(v_svc,0),
    'total_cents', v_items + v_dep + COALESCE(v_zone,0) + COALESCE(v_svc,0),
    'in_zone', v_in_zone);
END;
$$;
REVOKE ALL ON FUNCTION public.gas_quote(uuid, jsonb, double precision, double precision) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gas_quote(uuid, jsonb, double precision, double precision) TO authenticated;
NOTIFY pgrst, 'reload schema';
