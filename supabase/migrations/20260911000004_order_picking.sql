-- ════════════════════════════════════════════════════════════════════════════
-- Grocery order picking / fulfilment.
--
-- Lets in-store staff mark each order line as picked — by scanning the product
-- barcode or tapping — so a partly-shopped order is never lost and staff can see
-- what's left. Adds:
--   • order_items.picked_quantity / picked_at      (progress per line)
--   • menus.barcode                                (scan code, per store)
--   • pick_scan()       — atomic "scanned one of this item" by code
--   • pick_set_item()   — manual set of a line's picked count (+/- / done)
--   • assign_barcode()  — scan-to-assign an unknown code to a product
--
-- All writes go through SECURITY DEFINER RPCs gated to the store's owner or an
-- admin (same posture as the inventory RPCs) — no direct-write RLS is added.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Columns ───────────────────────────────────────────────────────────────
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS picked_quantity INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS picked_at       TIMESTAMPTZ;

ALTER TABLE public.order_items DROP CONSTRAINT IF EXISTS order_items_picked_nonneg;
ALTER TABLE public.order_items ADD CONSTRAINT order_items_picked_nonneg
  CHECK (picked_quantity >= 0);

-- Barcode is the physical scan code (EAN/UPC/etc). It is per-store, not global —
-- two stores can stock the same product with the same barcode — so uniqueness is
-- scoped to (store, barcode) for grocery products.
ALTER TABLE public.menus ADD COLUMN IF NOT EXISTS barcode TEXT;

DROP INDEX IF EXISTS public.menus_store_barcode_uniq;
CREATE UNIQUE INDEX menus_store_barcode_uniq
  ON public.menus (restaurant_id, barcode)
  WHERE barcode IS NOT NULL AND product_type = 'grocery';

-- ── 2. Shared: is the caller allowed to fulfil this order? ───────────────────
CREATE OR REPLACE FUNCTION public._can_fulfil_order(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT EXISTS (
    SELECT 1 FROM public.orders o
    WHERE o.id = p_order_id
      AND (public.current_user_owns_restaurant(o.restaurant_id)
           OR public.current_user_is_admin())
  );
$fn$;
REVOKE EXECUTE ON FUNCTION public._can_fulfil_order(UUID) FROM PUBLIC, anon;

-- ── 3. Order-level "everything picked?" helper ──────────────────────────────
CREATE OR REPLACE FUNCTION public._order_all_picked(p_order_id UUID)
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT NOT EXISTS (
    SELECT 1 FROM public.order_items i
    WHERE i.order_id = p_order_id AND i.picked_quantity < i.quantity
  );
$fn$;
REVOKE EXECUTE ON FUNCTION public._order_all_picked(UUID) FROM PUBLIC, anon;

-- ── 4. Scan one unit of an item by code (barcode or sku) ────────────────────
-- Returns JSONB with a `status`:
--   'picked'           – matched a line and incremented it (line_done tells you)
--   'already_complete' – matched a line already fully picked
--   'not_in_order'     – code matches a store product not on this order
--   'unknown_code'     – no product in this store carries that code (offer to
--                        scan-to-assign it to one of the order's lines)
CREATE OR REPLACE FUNCTION public.pick_scan(p_order_id UUID, p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_store  UUID;
  v_pid    UUID;
  v_pname  TEXT;
  v_oi     RECORD;
  v_code   TEXT := NULLIF(btrim(p_code), '');
BEGIN
  SELECT restaurant_id INTO v_store FROM public.orders WHERE id = p_order_id;
  IF v_store IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
  IF NOT public._can_fulfil_order(p_order_id) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;
  IF v_code IS NULL THEN RAISE EXCEPTION 'Empty scan code'; END IF;

  -- match a grocery product in THIS store by barcode or sku
  SELECT id, name INTO v_pid, v_pname
    FROM public.menus
   WHERE restaurant_id = v_store
     AND product_type = 'grocery'
     AND (barcode = v_code OR (sku IS NOT NULL AND sku = v_code))
   LIMIT 1;

  IF v_pid IS NULL THEN
    RETURN jsonb_build_object('status','unknown_code','code',v_code);
  END IF;

  -- find a line for this product that still needs picking; lock it
  SELECT id, quantity, picked_quantity INTO v_oi
    FROM public.order_items
   WHERE order_id = p_order_id AND menu_item_id = v_pid
   ORDER BY (picked_quantity < quantity) DESC, picked_quantity ASC
   LIMIT 1
   FOR UPDATE;

  IF v_oi.id IS NULL THEN
    RETURN jsonb_build_object('status','not_in_order','product_name',v_pname);
  END IF;

  IF v_oi.picked_quantity >= v_oi.quantity THEN
    RETURN jsonb_build_object('status','already_complete',
      'order_item_id',v_oi.id,'product_name',v_pname,
      'picked_quantity',v_oi.picked_quantity,'quantity',v_oi.quantity,
      'all_picked', public._order_all_picked(p_order_id));
  END IF;

  UPDATE public.order_items
     SET picked_quantity = v_oi.picked_quantity + 1,
         picked_at = CASE WHEN v_oi.picked_quantity + 1 >= quantity
                          THEN now() ELSE NULL END
   WHERE id = v_oi.id;

  RETURN jsonb_build_object('status','picked',
    'order_item_id',v_oi.id,'product_name',v_pname,
    'picked_quantity',v_oi.picked_quantity + 1,'quantity',v_oi.quantity,
    'line_done', (v_oi.picked_quantity + 1 >= v_oi.quantity),
    'all_picked', public._order_all_picked(p_order_id));
END;
$fn$;

-- ── 5. Manually set a line's picked count (tap +/- or mark done/undone) ──────
CREATE OR REPLACE FUNCTION public.pick_set_item(
  p_order_item_id UUID,
  p_picked_quantity INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_order UUID; v_qty INTEGER; v_new INTEGER;
BEGIN
  SELECT order_id, quantity INTO v_order, v_qty
    FROM public.order_items WHERE id = p_order_item_id FOR UPDATE;
  IF v_order IS NULL THEN RAISE EXCEPTION 'Order item not found'; END IF;
  IF NOT public._can_fulfil_order(v_order) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;

  v_new := GREATEST(0, LEAST(COALESCE(p_picked_quantity,0), v_qty));
  UPDATE public.order_items
     SET picked_quantity = v_new,
         picked_at = CASE WHEN v_new >= v_qty THEN now() ELSE NULL END
   WHERE id = p_order_item_id;

  RETURN jsonb_build_object('status','ok','order_item_id',p_order_item_id,
    'picked_quantity',v_new,'quantity',v_qty,'line_done',(v_new >= v_qty),
    'all_picked', public._order_all_picked(v_order));
END;
$fn$;

-- ── 6. Scan-to-assign: link an unknown code to a product ────────────────────
CREATE OR REPLACE FUNCTION public.assign_barcode(
  p_product_id UUID,
  p_barcode    TEXT
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_store UUID; v_code TEXT := NULLIF(btrim(p_barcode), '');
BEGIN
  IF v_code IS NULL THEN RAISE EXCEPTION 'Empty barcode'; END IF;
  SELECT restaurant_id INTO v_store FROM public.menus WHERE id = p_product_id;
  IF v_store IS NULL THEN RAISE EXCEPTION 'Product not found'; END IF;
  IF NOT (public.current_user_owns_restaurant(v_store) OR public.current_user_is_admin()) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;

  BEGIN
    UPDATE public.menus SET barcode = v_code, updated_at = now()
     WHERE id = p_product_id;
  EXCEPTION WHEN unique_violation THEN
    RAISE EXCEPTION 'That barcode is already linked to another product in this store'
      USING errcode = 'unique_violation';
  END;
END;
$fn$;

-- ── Grants ──────────────────────────────────────────────────────────────────
DO $grants$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('pick_scan','pick_set_item','assign_barcode')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END
$grants$;

NOTIFY pgrst, 'reload schema';
