-- ════════════════════════════════════════════════════════════════════════════
-- Grocery inventory system.
--
-- Before this, a grocery product (a menus row, product_type='grocery') had only
-- a manual in_stock boolean and a per-order max_quantity cap; sales never
-- decremented anything. This adds real quantity tracking, an append-only
-- movement ledger, and atomic RPCs so stock can't be oversold or edited
-- without an audit trail.
--
-- track_inventory is opt-in per product and defaults false, so every existing
-- product (grocery and food) behaves exactly as before until a store turns
-- tracking on. Nothing here changes the order flow yet — that is a separate,
-- deliberate step.
-- ════════════════════════════════════════════════════════════════════════════

-- ── 1. Product-level inventory fields ───────────────────────────────────────
ALTER TABLE public.menus
  ADD COLUMN IF NOT EXISTS track_inventory     BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS stock_quantity      INTEGER NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS low_stock_threshold INTEGER NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS sku                 TEXT,
  ADD COLUMN IF NOT EXISTS cost_price          NUMERIC;

-- Stock can never be negative; the RPCs enforce it, this is the backstop.
ALTER TABLE public.menus DROP CONSTRAINT IF EXISTS menus_stock_nonneg;
ALTER TABLE public.menus ADD CONSTRAINT menus_stock_nonneg
  CHECK (stock_quantity >= 0);

-- ── 2. Movement ledger (append-only audit trail) ────────────────────────────
CREATE TABLE IF NOT EXISTS public.inventory_movements (
  id             BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  product_id     UUID NOT NULL REFERENCES public.menus(id) ON DELETE CASCADE,
  store_id       UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  change         INTEGER NOT NULL,          -- signed: +restock, -sale, ±adjust
  balance_after  INTEGER NOT NULL,
  reason         TEXT NOT NULL CHECK (reason IN
                   ('restock','sale','adjustment','waste','stocktake',
                    'order_restored')),
  order_id       UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  note           TEXT,
  actor_id       UUID REFERENCES public.users(id) ON DELETE SET NULL,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS inventory_movements_product_idx
  ON public.inventory_movements (product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS inventory_movements_store_idx
  ON public.inventory_movements (store_id, created_at DESC);

ALTER TABLE public.inventory_movements ENABLE ROW LEVEL SECURITY;

-- Read: the store's owner or an admin. Writes happen only through the RPCs
-- below (SECURITY DEFINER), never directly — so there is no INSERT/UPDATE
-- policy on purpose.
DROP POLICY IF EXISTS inventory_movements_read ON public.inventory_movements;
CREATE POLICY inventory_movements_read ON public.inventory_movements
  FOR SELECT TO authenticated
  USING (public.current_user_owns_restaurant(store_id)
         OR public.current_user_is_admin());

-- ── 3. Shared write helper ──────────────────────────────────────────────────
-- Applies a signed change to one product, writes the ledger row, and keeps
-- in_stock in sync with the quantity. Locks the row so concurrent sales /
-- restocks can't race. store ownership / admin is checked by the callers.
CREATE OR REPLACE FUNCTION public._apply_inventory_change(
  p_product_id UUID,
  p_change     INTEGER,
  p_reason     TEXT,
  p_note       TEXT,
  p_order_id   UUID,
  p_actor      UUID
)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_store   UUID;
  v_qty     INTEGER;
  v_new     INTEGER;
BEGIN
  SELECT restaurant_id, stock_quantity INTO v_store, v_qty
    FROM public.menus WHERE id = p_product_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Product % not found', p_product_id;
  END IF;

  v_new := COALESCE(v_qty, 0) + p_change;
  IF v_new < 0 THEN
    RAISE EXCEPTION 'Insufficient stock: have %, change %', COALESCE(v_qty,0), p_change
      USING errcode = 'check_violation';
  END IF;

  UPDATE public.menus
     SET stock_quantity = v_new,
         in_stock       = (v_new > 0),
         track_inventory = true,
         updated_at     = now()
   WHERE id = p_product_id;

  INSERT INTO public.inventory_movements
    (product_id, store_id, change, balance_after, reason, order_id, note, actor_id)
  VALUES
    (p_product_id, v_store, p_change, v_new, p_reason, p_order_id, p_note, p_actor);

  RETURN v_new;
END;
$fn$;

REVOKE EXECUTE ON FUNCTION public._apply_inventory_change(UUID,INTEGER,TEXT,TEXT,UUID,UUID) FROM PUBLIC, anon, authenticated;

-- ── 4. Owner/admin: adjust by a delta (restock / waste / manual adjustment) ─
CREATE OR REPLACE FUNCTION public.adjust_inventory(
  p_product_id UUID,
  p_change     INTEGER,
  p_reason     TEXT DEFAULT 'adjustment',
  p_note       TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_store UUID;
BEGIN
  IF p_reason NOT IN ('restock','adjustment','waste') THEN
    RAISE EXCEPTION 'Invalid reason %. Use restock, adjustment or waste', p_reason;
  END IF;
  IF p_change = 0 THEN
    RAISE EXCEPTION 'Change cannot be zero';
  END IF;

  SELECT restaurant_id INTO v_store FROM public.menus WHERE id = p_product_id;
  IF v_store IS NULL THEN RAISE EXCEPTION 'Product not found'; END IF;
  IF NOT (public.current_user_owns_restaurant(v_store) OR public.current_user_is_admin()) THEN
    RAISE EXCEPTION 'Forbidden: not your store' USING errcode = 'insufficient_privilege';
  END IF;

  RETURN public._apply_inventory_change(
    p_product_id, p_change, p_reason, p_note, NULL, auth.uid());
END;
$fn$;

-- ── 5. Owner/admin: set an absolute count (stocktake) ───────────────────────
CREATE OR REPLACE FUNCTION public.set_inventory(
  p_product_id UUID,
  p_new_qty    INTEGER,
  p_note       TEXT DEFAULT NULL
)
RETURNS INTEGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_store UUID; v_qty INTEGER; v_delta INTEGER;
BEGIN
  IF p_new_qty < 0 THEN RAISE EXCEPTION 'Quantity cannot be negative'; END IF;

  SELECT restaurant_id, stock_quantity INTO v_store, v_qty
    FROM public.menus WHERE id = p_product_id;
  IF v_store IS NULL THEN RAISE EXCEPTION 'Product not found'; END IF;
  IF NOT (public.current_user_owns_restaurant(v_store) OR public.current_user_is_admin()) THEN
    RAISE EXCEPTION 'Forbidden: not your store' USING errcode = 'insufficient_privilege';
  END IF;

  v_delta := p_new_qty - COALESCE(v_qty, 0);
  IF v_delta = 0 THEN RETURN p_new_qty; END IF;
  RETURN public._apply_inventory_change(
    p_product_id, v_delta, 'stocktake', p_note, NULL, auth.uid());
END;
$fn$;

-- ── 6. Order flow: consume stock for a sale (server-only) ───────────────────
-- Called by the grocery order edge function (service role). Decrements each
-- tracked item atomically and RAISES if any is short, so the order fails rather
-- than overselling. Untracked products are ignored (behave as before).
-- Not callable by ordinary users: a JWT caller who is not an admin is rejected,
-- so it cannot be used to grief a store's stock.
CREATE OR REPLACE FUNCTION public.consume_inventory_for_order(
  p_items    JSONB,     -- [{ "product_id": uuid, "quantity": int }, ...]
  p_order_id UUID
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  v_item   JSONB;
  v_pid    UUID;
  v_qty    INTEGER;
  v_track  BOOLEAN;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.current_user_is_admin() THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_pid := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::int;
    IF v_pid IS NULL OR v_qty IS NULL OR v_qty <= 0 THEN CONTINUE; END IF;

    SELECT track_inventory INTO v_track FROM public.menus WHERE id = v_pid;
    IF NOT COALESCE(v_track, false) THEN CONTINUE; END IF;  -- untracked: skip

    PERFORM public._apply_inventory_change(
      v_pid, -v_qty, 'sale', NULL, p_order_id, NULL);
  END LOOP;
END;
$fn$;

-- ── 7. Order flow: restore stock when an order is cancelled ─────────────────
-- Reverses this order's sale movements exactly once (idempotent: it only acts
-- on sale rows that have not already been restored).
CREATE OR REPLACE FUNCTION public.restore_inventory_for_order(
  p_order_id UUID
)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE r RECORD;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.current_user_is_admin() THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;

  FOR r IN
    SELECT m.product_id, SUM(-m.change)::int AS qty
    FROM public.inventory_movements m
    WHERE m.order_id = p_order_id AND m.reason = 'sale'
    GROUP BY m.product_id
    -- only if not already restored
    HAVING NOT EXISTS (
      SELECT 1 FROM public.inventory_movements r2
      WHERE r2.order_id = p_order_id AND r2.reason = 'order_restored'
        AND r2.product_id = m.product_id)
  LOOP
    PERFORM public._apply_inventory_change(
      r.product_id, r.qty, 'order_restored', 'Order cancelled', p_order_id, NULL);
  END LOOP;
END;
$fn$;

-- ── 8. Low-stock view for a store (owner/admin) ─────────────────────────────
CREATE OR REPLACE FUNCTION public.store_low_stock(p_store_id UUID)
RETURNS TABLE (product_id UUID, name TEXT, stock_quantity INTEGER,
               low_stock_threshold INTEGER, in_stock BOOLEAN)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $fn$
  SELECT m.id, m.name, m.stock_quantity, m.low_stock_threshold, m.in_stock
  FROM public.menus m
  WHERE m.restaurant_id = p_store_id
    AND m.product_type = 'grocery'
    AND m.track_inventory
    AND m.stock_quantity <= m.low_stock_threshold
    AND (public.current_user_owns_restaurant(p_store_id) OR public.current_user_is_admin())
  ORDER BY m.stock_quantity ASC, m.name;
$fn$;

-- ── Grants ──────────────────────────────────────────────────────────────────
DO $grants$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig, p.proname
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.proname IN ('adjust_inventory','set_inventory','store_low_stock',
                        'consume_inventory_for_order','restore_inventory_for_order')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    -- Owner/admin RPCs: authenticated may call (they self-gate on ownership).
    -- The two order-flow RPCs also self-gate (service role / admin only).
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END
$grants$;

NOTIFY pgrst, 'reload schema';
