-- ============================================================================
-- HotBite Cooking Gas — Lifecycle RPCs (placement, state machine, exchanges,
-- delivery assignment). All SECURITY DEFINER, pinned to auth.uid(), with
-- server-authoritative pricing. Nothing here trusts a client-submitted total.
--
-- Payment capture (Stripe/NCB/wallet) is handled by the place-gas-order edge
-- function + webhooks later; these RPCs model the order + fulfilment flow:
--   place (pending_supplier, unpaid) → supplier accept → awaiting_payment →
--   payment_confirmed → preparing → assigned → out_for_delivery → delivered →
--   [exchange_completed] → completed.  Deposits are liabilities, not revenue.
-- ============================================================================

-- ── Internal: resolve the caller's role relative to a gas order ─────────────
CREATE OR REPLACE FUNCTION public._gas_actor_role(p_order uuid)
RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT CASE
    WHEN public.is_admin() THEN 'admin'
    WHEN EXISTS (SELECT 1 FROM public.gas_orders o
                 WHERE o.id = p_order AND public.can_manage_gas_supplier(o.supplier_id)) THEN 'supplier'
    WHEN EXISTS (SELECT 1 FROM public.gas_orders o
                 WHERE o.id = p_order AND o.customer_id = auth.uid()) THEN 'customer'
    ELSE NULL
  END;
$$;
REVOKE ALL ON FUNCTION public._gas_actor_role(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public._gas_actor_role(uuid) TO authenticated;

-- ── Placement ───────────────────────────────────────────────────────────────
-- p_items: jsonb array of
--   { "product_id": uuid, "purchase_type": "exchange"|"new", "qty": int,
--     "exchange": { "existing_brand","existing_size","condition","collectible",
--                   "photo_path" }  -- required when purchase_type='exchange'
--   }
-- Recomputes every cent from gas_products + gas_settings + zone fee. Validates
-- supplier is live, products active & in stock & buyable the chosen way, and the
-- delivery point is inside a supplier zone. Reserves stock atomically. Creates
-- the order 'pending_supplier'/'unpaid' (payment happens after supplier accepts).
CREATE OR REPLACE FUNCTION public.place_gas_order(
  p_supplier       uuid,
  p_items          jsonb,
  p_address        text,
  p_lat            double precision,
  p_lng            double precision,
  p_address_id     uuid DEFAULT NULL,
  p_payment_method text DEFAULT 'wallet',
  p_notes          text DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_customer    uuid := auth.uid();
  v_order       uuid;
  v_enabled     boolean;
  v_svc_fee     bigint;
  v_zone_fee    bigint;
  v_item        jsonb;
  v_prod        public.gas_products%ROWTYPE;
  v_qty         int;
  v_ptype       text;
  v_unit        bigint;
  v_items_cents bigint := 0;
  v_dep_cents   bigint := 0;
  v_total       bigint;
BEGIN
  IF v_customer IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  SELECT enabled, service_fee_cents INTO v_enabled, v_svc_fee FROM public.gas_settings WHERE id = 1;
  IF NOT COALESCE(v_enabled, false) THEN
    RAISE EXCEPTION 'gas ordering is not enabled' USING ERRCODE = 'P0001';
  END IF;

  -- supplier must be live
  IF NOT EXISTS (SELECT 1 FROM public.gas_suppliers s
                 WHERE s.id = p_supplier AND s.verification_status = 'approved'
                   AND s.is_active = true AND s.accepting_orders = true
                   AND s.delivery_operational = true) THEN
    RAISE EXCEPTION 'supplier is not available' USING ERRCODE = 'P0001';
  END IF;

  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'no items' USING ERRCODE = '22023';
  END IF;

  -- delivery point must be inside an active zone of this supplier → zone fee
  SELECT delivery_fee_cents INTO v_zone_fee
  FROM public.gas_delivery_zones z
  WHERE z.supplier_id = p_supplier AND z.is_active = true
    AND p_lat IS NOT NULL AND p_lng IS NOT NULL
    AND (6371 * acos(greatest(-1, least(1,
          cos(radians(z.center_lat)) * cos(radians(p_lat)) *
          cos(radians(p_lng) - radians(z.center_lng)) +
          sin(radians(z.center_lat)) * sin(radians(p_lat)))))) <= z.radius_km
  ORDER BY z.delivery_fee_cents ASC
  LIMIT 1;
  IF v_zone_fee IS NULL THEN
    RAISE EXCEPTION 'delivery address is outside the supplier delivery area' USING ERRCODE = 'P0001';
  END IF;

  -- create the order shell first so line rows + exchanges can reference it
  INSERT INTO public.gas_orders (
    customer_id, supplier_id, address_id, delivery_address, delivery_lat, delivery_lng,
    delivery_cents, service_fee_cents, payment_method, notes, status, payment_status)
  VALUES (v_customer, p_supplier, p_address_id, p_address, p_lat, p_lng,
          v_zone_fee, COALESCE(v_svc_fee, 0), COALESCE(p_payment_method, 'wallet'),
          p_notes, 'pending_supplier', 'unpaid')
  RETURNING id INTO v_order;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_ptype := v_item->>'purchase_type';
    v_qty   := COALESCE((v_item->>'qty')::int, 0);
    IF v_qty <= 0 THEN RAISE EXCEPTION 'invalid qty' USING ERRCODE = '22023'; END IF;
    IF v_ptype NOT IN ('exchange','new') THEN
      RAISE EXCEPTION 'invalid purchase_type' USING ERRCODE = '22023';
    END IF;

    -- lock the product row to reserve stock safely under concurrency
    SELECT * INTO v_prod FROM public.gas_products
      WHERE id = (v_item->>'product_id')::uuid AND supplier_id = p_supplier
      FOR UPDATE;
    IF NOT FOUND OR NOT v_prod.is_active THEN
      RAISE EXCEPTION 'product unavailable' USING ERRCODE = 'P0001';
    END IF;
    IF v_prod.stock_qty < v_qty THEN
      RAISE EXCEPTION 'insufficient stock' USING ERRCODE = 'P0001';
    END IF;

    IF v_ptype = 'exchange' THEN
      IF NOT v_prod.exchange_available OR v_prod.exchange_price_cents IS NULL THEN
        RAISE EXCEPTION 'exchange not offered for this product' USING ERRCODE = 'P0001';
      END IF;
      v_unit := v_prod.exchange_price_cents;
    ELSE
      IF NOT v_prod.new_available OR v_prod.new_price_cents IS NULL THEN
        RAISE EXCEPTION 'new cylinder not offered for this product' USING ERRCODE = 'P0001';
      END IF;
      v_unit := v_prod.new_price_cents;
    END IF;

    INSERT INTO public.gas_order_items (
      order_id, product_id, brand, size_label, purchase_type, qty, unit_price_cents, deposit_cents)
    VALUES (v_order, v_prod.id, v_prod.brand, v_prod.size_label, v_ptype, v_qty, v_unit,
            CASE WHEN v_ptype = 'new' THEN v_prod.deposit_cents ELSE 0 END);

    v_items_cents := v_items_cents + v_unit * v_qty;
    IF v_ptype = 'new' THEN
      v_dep_cents := v_dep_cents + v_prod.deposit_cents * v_qty;
    END IF;

    -- exchange record (supplier must approve; NEVER auto-approved)
    IF v_ptype = 'exchange' THEN
      INSERT INTO public.gas_cylinder_exchanges (
        order_id, existing_brand, existing_size, condition_declared, collectible, photo_path)
      VALUES (v_order,
        v_item->'exchange'->>'existing_brand',
        v_item->'exchange'->>'existing_size',
        v_item->'exchange'->>'condition',
        COALESCE((v_item->'exchange'->>'collectible')::boolean, true),
        v_item->'exchange'->>'photo_path');
    END IF;

    -- reserve stock + ledger
    UPDATE public.gas_products SET stock_qty = stock_qty - v_qty, updated_at = now()
      WHERE id = v_prod.id;
    INSERT INTO public.gas_inventory_movements (product_id, delta, reason, order_id)
      VALUES (v_prod.id, -v_qty, 'reserve', v_order);
  END LOOP;

  v_total := v_items_cents + v_dep_cents + v_zone_fee + COALESCE(v_svc_fee, 0);

  UPDATE public.gas_orders
     SET items_cents = v_items_cents, deposit_cents = v_dep_cents, total_cents = v_total
   WHERE id = v_order;

  INSERT INTO public.gas_order_events (order_id, prev_status, new_status, actor_role, reason)
    VALUES (v_order, NULL, 'pending_supplier', 'customer', 'order placed');

  RETURN v_order;
END;
$$;
REVOKE ALL ON FUNCTION public.place_gas_order(uuid, jsonb, text, double precision, double precision, uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.place_gas_order(uuid, jsonb, text, double precision, double precision, uuid, text, text) TO authenticated;

-- ── State machine transition (validated + role-gated) ───────────────────────
CREATE OR REPLACE FUNCTION public.gas_order_transition(
  p_order uuid, p_new text, p_reason text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_role text := public._gas_actor_role(p_order);
  v_cur  text;
  v_ok   boolean;
BEGIN
  IF v_role IS NULL THEN RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501'; END IF;
  SELECT status INTO v_cur FROM public.gas_orders WHERE id = p_order FOR UPDATE;
  IF v_cur IS NULL THEN RAISE EXCEPTION 'order not found' USING ERRCODE = 'P0002'; END IF;

  -- allowed transitions
  v_ok := CASE v_cur
    WHEN 'pending_supplier'   THEN p_new IN ('supplier_accepted','rejected','cancelled')
    WHEN 'supplier_accepted'  THEN p_new IN ('awaiting_payment','cancelled')
    WHEN 'awaiting_payment'   THEN p_new IN ('payment_confirmed','cancelled')
    WHEN 'payment_confirmed'  THEN p_new IN ('preparing','refund_pending')
    WHEN 'preparing'          THEN p_new IN ('assigned','refund_pending')
    WHEN 'assigned'           THEN p_new IN ('out_for_delivery','refund_pending')
    WHEN 'out_for_delivery'   THEN p_new IN ('delivered','failed_delivery')
    WHEN 'delivered'          THEN p_new IN ('exchange_completed','completed')
    WHEN 'exchange_completed' THEN p_new IN ('completed')
    WHEN 'failed_delivery'    THEN p_new IN ('assigned','refund_pending')
    WHEN 'refund_pending'     THEN p_new IN ('refunded')
    ELSE false  -- cancelled/rejected/refunded/completed are terminal
  END;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'invalid transition % -> %', v_cur, p_new USING ERRCODE = 'P0001';
  END IF;

  -- role authorisation
  IF v_role = 'customer' THEN
    IF NOT (p_new = 'cancelled' AND v_cur IN ('pending_supplier','supplier_accepted','awaiting_payment')) THEN
      RAISE EXCEPTION 'not permitted for customer' USING ERRCODE = '42501';
    END IF;
  ELSIF v_role = 'supplier' THEN
    -- supplier drives fulfilment but NOT payment_confirmed / refunded (money)
    IF p_new IN ('payment_confirmed','refunded') THEN
      RAISE EXCEPTION 'not permitted for supplier' USING ERRCODE = '42501';
    END IF;
  END IF;
  -- admin: anything allowed by the state machine

  -- if the order is being cancelled/rejected before delivery, restore reserved stock
  IF p_new IN ('cancelled','rejected') THEN
    PERFORM public._gas_restore_stock(p_order);
  END IF;

  UPDATE public.gas_orders SET
    status = p_new,
    reject_reason = CASE WHEN p_new = 'rejected' THEN p_reason ELSE reject_reason END,
    cancel_reason = CASE WHEN p_new = 'cancelled' THEN p_reason ELSE cancel_reason END,
    accepted_at   = CASE WHEN p_new = 'supplier_accepted' THEN now() ELSE accepted_at END,
    delivered_at  = CASE WHEN p_new = 'delivered' THEN now() ELSE delivered_at END,
    completed_at  = CASE WHEN p_new = 'completed' THEN now() ELSE completed_at END,
    updated_at    = now()
  WHERE id = p_order;

  INSERT INTO public.gas_order_events (order_id, prev_status, new_status, actor_role, reason)
    VALUES (p_order, v_cur, p_new, v_role, p_reason);
END;
$$;
REVOKE ALL ON FUNCTION public.gas_order_transition(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gas_order_transition(uuid, text, text) TO authenticated;

-- ── Internal: restore reserved stock for an order's items ───────────────────
CREATE OR REPLACE FUNCTION public._gas_restore_stock(p_order uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record;
BEGIN
  -- Aggregate qty PER PRODUCT (an order may have several lines for one product,
  -- e.g. an exchange line and a new-cylinder line of the same cylinder). The
  -- per-(order,product) guard makes the whole restore idempotent.
  FOR r IN SELECT product_id, sum(qty)::int AS qty FROM public.gas_order_items
           WHERE order_id = p_order AND product_id IS NOT NULL
           GROUP BY product_id LOOP
    IF NOT EXISTS (SELECT 1 FROM public.gas_inventory_movements
                   WHERE order_id = p_order AND product_id = r.product_id AND reason = 'restore') THEN
      UPDATE public.gas_products SET stock_qty = stock_qty + r.qty, updated_at = now()
        WHERE id = r.product_id;
      INSERT INTO public.gas_inventory_movements (product_id, delta, reason, order_id)
        VALUES (r.product_id, r.qty, 'restore', p_order);
    END IF;
  END LOOP;
END;
$$;
REVOKE ALL ON FUNCTION public._gas_restore_stock(uuid) FROM PUBLIC, anon;

-- ── Supplier: decide a cylinder exchange (NEVER auto-approved from a photo) ──
CREATE OR REPLACE FUNCTION public.gas_exchange_decide(
  p_exchange uuid, p_decision text, p_reason text DEFAULT NULL,
  p_price_adjust_cents bigint DEFAULT 0,
  p_replacement_brand text DEFAULT NULL, p_replacement_size text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_order uuid; v_supplier uuid;
BEGIN
  SELECT e.order_id, o.supplier_id INTO v_order, v_supplier
    FROM public.gas_cylinder_exchanges e JOIN public.gas_orders o ON o.id = e.order_id
    WHERE e.id = p_exchange;
  IF v_order IS NULL THEN RAISE EXCEPTION 'exchange not found' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.can_manage_gas_supplier(v_supplier) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;
  IF p_decision NOT IN ('approved','rejected','alternative_offered') THEN
    RAISE EXCEPTION 'invalid decision' USING ERRCODE = '22023';
  END IF;
  UPDATE public.gas_cylinder_exchanges SET
    supplier_decision = p_decision, decision_reason = p_reason,
    price_adjust_cents = COALESCE(p_price_adjust_cents, 0),
    replacement_brand = p_replacement_brand, replacement_size = p_replacement_size,
    decided_by = auth.uid()
  WHERE id = p_exchange;
END;
$$;
REVOKE ALL ON FUNCTION public.gas_exchange_decide(uuid, text, text, bigint, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gas_exchange_decide(uuid, text, text, bigint, text, text) TO authenticated;

-- ── Supplier: assign an eligible authorised delivery operator ───────────────
CREATE OR REPLACE FUNCTION public.gas_assign_operator(
  p_order uuid, p_operator uuid, p_payout_cents bigint DEFAULT 0
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_supplier uuid; v_require_checks boolean;
BEGIN
  SELECT supplier_id INTO v_supplier FROM public.gas_orders WHERE id = p_order;
  IF v_supplier IS NULL THEN RAISE EXCEPTION 'order not found' USING ERRCODE = 'P0002'; END IF;
  IF NOT public.can_manage_gas_supplier(v_supplier) THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE = '42501';
  END IF;

  SELECT require_operator_checks INTO v_require_checks FROM public.gas_settings WHERE id = 1;
  -- operator must belong to this supplier, be active, and (when checks required) eligible.
  IF NOT EXISTS (SELECT 1 FROM public.gas_delivery_operators op
                 WHERE op.id = p_operator AND op.supplier_id = v_supplier
                   AND op.is_active = true
                   AND (NOT COALESCE(v_require_checks, true) OR op.eligible = true)) THEN
    RAISE EXCEPTION 'operator not eligible for gas delivery' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.gas_delivery_assignments (order_id, operator_id, payout_cents)
    VALUES (p_order, p_operator, COALESCE(p_payout_cents, 0));
  UPDATE public.gas_orders SET operator_id = p_operator, updated_at = now() WHERE id = p_order;
  -- move to 'assigned' if currently preparing
  IF (SELECT status FROM public.gas_orders WHERE id = p_order) = 'preparing' THEN
    PERFORM public.gas_order_transition(p_order, 'assigned', 'operator assigned');
  END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.gas_assign_operator(uuid, uuid, bigint) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.gas_assign_operator(uuid, uuid, bigint) TO authenticated;

NOTIFY pgrst, 'reload schema';
