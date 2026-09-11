-- Restore grocery stock whenever an order is cancelled, via any path. The RPC
-- is idempotent (it won't restore twice), so re-firing on repeated updates is
-- harmless. Fires only on the transition INTO 'cancelled'.
CREATE OR REPLACE FUNCTION public.trg_restore_inventory_on_cancel()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
BEGIN
  IF NEW.status = 'cancelled' AND OLD.status IS DISTINCT FROM 'cancelled' THEN
    PERFORM public.restore_inventory_for_order(NEW.id);
  END IF;
  RETURN NULL;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_restore_inventory_on_cancel ON public.orders;
CREATE TRIGGER trg_restore_inventory_on_cancel
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.trg_restore_inventory_on_cancel();

NOTIFY pgrst, 'reload schema';
