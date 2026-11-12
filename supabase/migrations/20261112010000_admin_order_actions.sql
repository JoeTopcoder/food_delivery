-- Admin per-order action toolkit: notes, block customer, edit delivery fee,
-- change payment method, edit order item. All admin-gated & audited.
BEGIN;

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS admin_notes text;
ALTER TABLE public.users  ADD COLUMN IF NOT EXISTS blocked_at timestamptz;
ALTER TABLE public.users  ADD COLUMN IF NOT EXISTS blocked_reason text;
-- is_active already exists on users; blocking sets is_active = false.

-- ── Order admin notes ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_set_order_notes(
  p_order_id uuid, p_notes text, p_admin_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_admin uuid;
BEGIN
  v_admin := public.require_admin(p_admin_id);
  UPDATE orders SET admin_notes = p_notes, updated_at = now() WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found'; END IF;
  RETURN jsonb_build_object('ok', true, 'admin_notes', p_notes);
END; $fn$;

-- ── Block / unblock a customer ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_block_customer(
  p_user_id uuid, p_blocked boolean, p_reason text, p_admin_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_admin uuid;
BEGIN
  v_admin := public.require_admin(p_admin_id);
  UPDATE users
     SET is_active      = NOT p_blocked,
         blocked_at     = CASE WHEN p_blocked THEN now() ELSE NULL END,
         blocked_reason = CASE WHEN p_blocked THEN p_reason ELSE NULL END,
         updated_at     = now()
   WHERE id = p_user_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Customer not found'; END IF;
  RETURN jsonb_build_object('ok', true, 'blocked', p_blocked);
END; $fn$;

-- ── Edit delivery fee (recomputes tax-on-delivery and the order total) ───────
CREATE OR REPLACE FUNCTION public.admin_edit_delivery_fee(
  p_order_id uuid, p_new_fee numeric, p_admin_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_admin uuid; v_old_del numeric; v_old_tax numeric; v_total numeric;
  v_rate numeric; v_new_tax numeric; v_new_total numeric;
BEGIN
  v_admin := public.require_admin(p_admin_id);
  IF p_new_fee IS NULL OR p_new_fee < 0 THEN RAISE EXCEPTION 'Delivery fee must be >= 0'; END IF;
  SELECT delivery_fee, tax_amount, total_amount INTO v_old_del, v_old_tax, v_total
    FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found'; END IF;

  -- Effective tax rate: derive from the existing delivery tax, else the config.
  v_rate := CASE WHEN COALESCE(v_old_del,0) > 0 THEN COALESCE(v_old_tax,0)/v_old_del
                 ELSE COALESCE((SELECT value::numeric FROM app_config WHERE key='tax_rate'), 0) END;
  v_new_tax   := round((p_new_fee * v_rate)::numeric, 2);
  v_new_total := round((COALESCE(v_total,0) - COALESCE(v_old_del,0) - COALESCE(v_old_tax,0)
                        + p_new_fee + v_new_tax)::numeric, 2);

  UPDATE orders SET delivery_fee = p_new_fee, tax_amount = v_new_tax,
                    total_amount = v_new_total, updated_at = now()
   WHERE id = p_order_id;
  RETURN jsonb_build_object('ok', true, 'delivery_fee', p_new_fee,
                            'tax_amount', v_new_tax, 'total_amount', v_new_total);
END; $fn$;

-- ── Change payment method ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_change_payment_method(
  p_order_id uuid, p_method text, p_admin_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_admin uuid; v_m text;
BEGIN
  v_admin := public.require_admin(p_admin_id);
  v_m := lower(trim(p_method));
  IF v_m NOT IN ('cash','card','stripe','wallet') THEN
    RAISE EXCEPTION 'Invalid payment method %', p_method;
  END IF;
  -- Card/wallet methods must carry a completed payment (payment gate). Recording
  -- the method as card/wallet asserts payment was taken; cash stays as-is.
  IF v_m IN ('card','stripe','wallet') THEN
    UPDATE orders SET payment_method = v_m, payment_status = 'completed', updated_at = now()
     WHERE id = p_order_id;
  ELSE
    UPDATE orders SET payment_method = v_m, updated_at = now() WHERE id = p_order_id;
  END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'Order not found'; END IF;
  RETURN jsonb_build_object('ok', true, 'payment_method', v_m);
END; $fn$;

-- ── Edit an order line item's quantity (recomputes order subtotal + total) ───
CREATE OR REPLACE FUNCTION public.admin_edit_order_item(
  p_item_id uuid, p_qty integer, p_admin_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_admin uuid; v_order uuid; v_price numeric; v_old_sub numeric;
  v_new_sub numeric; v_total numeric;
BEGIN
  v_admin := public.require_admin(p_admin_id);
  SELECT order_id, price INTO v_order, v_price FROM order_items WHERE id = p_item_id;
  IF v_order IS NULL THEN RAISE EXCEPTION 'Order item not found'; END IF;

  IF p_qty <= 0 THEN
    DELETE FROM order_items WHERE id = p_item_id;
  ELSE
    UPDATE order_items
       SET quantity = p_qty, subtotal = round((v_price * p_qty)::numeric, 2)
     WHERE id = p_item_id;
  END IF;

  SELECT round(COALESCE(sum(subtotal),0)::numeric,2) INTO v_new_sub
    FROM order_items WHERE order_id = v_order;
  SELECT subtotal, total_amount INTO v_old_sub, v_total FROM orders WHERE id = v_order;

  -- Tax is on delivery (unchanged); total shifts by the subtotal delta only.
  UPDATE orders
     SET subtotal = v_new_sub,
         total_amount = round((COALESCE(v_total,0) - COALESCE(v_old_sub,0) + v_new_sub)::numeric,2),
         updated_at = now()
   WHERE id = v_order;

  RETURN jsonb_build_object('ok', true, 'order_id', v_order, 'subtotal', v_new_sub);
END; $fn$;

-- Grants (admin-gated inside each function via require_admin).
REVOKE ALL ON FUNCTION public.admin_set_order_notes(uuid,text,uuid)       FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_block_customer(uuid,boolean,text,uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_edit_delivery_fee(uuid,numeric,uuid)   FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_change_payment_method(uuid,text,uuid)  FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_edit_order_item(uuid,integer,uuid)     FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_order_notes(uuid,text,uuid)       TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_block_customer(uuid,boolean,text,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_edit_delivery_fee(uuid,numeric,uuid)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_change_payment_method(uuid,text,uuid)  TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_edit_order_item(uuid,integer,uuid)     TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
