-- Fix: customer order cancellation failed with 42501 (Forbidden).
--
-- The cancel trigger (trg_restore_inventory_on_cancel) runs in the CANCELLING
-- user's context and called restore_inventory_for_order, whose guard rejects
-- any non-admin caller — so a customer cancelling their own order tripped the
-- guard and the whole UPDATE was aborted. That guard exists to stop a customer
-- calling the RPC DIRECTLY to grief stock; it must not block the legitimate
-- cancel path.
--
-- Split the work into a guard-free internal used by the trigger and the RPC,
-- and keep the auth guard only on the public RPC.

CREATE OR REPLACE FUNCTION public._restore_inventory_for_order(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT m.product_id, SUM(-m.change)::int AS qty
    FROM public.inventory_movements m
    WHERE m.order_id = p_order_id AND m.reason = 'sale'
    GROUP BY m.product_id
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
REVOKE EXECUTE ON FUNCTION public._restore_inventory_for_order(UUID) FROM PUBLIC, anon, authenticated;

-- Public RPC keeps the direct-call guard, then delegates to the internal.
CREATE OR REPLACE FUNCTION public.restore_inventory_for_order(p_order_id UUID)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.current_user_is_admin() THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;
  PERFORM public._restore_inventory_for_order(p_order_id);
END;
$fn$;

-- Trigger uses the guard-free internal: it only fires on a genuine status
-- transition INTO 'cancelled', which the orders RLS already authorises.
CREATE OR REPLACE FUNCTION public.trg_restore_inventory_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    PERFORM public._restore_inventory_for_order(NEW.id);
  END IF;
  RETURN NULL;
END;
$fn$;

NOTIFY pgrst, 'reload schema';
