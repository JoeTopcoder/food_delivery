-- Extend the app-closure guard to the multi-restaurant checkout header
-- (master_orders). It has no scheduled_for (multi-restaurant is immediate), so
-- it's blocked whenever TODAY is closed. Single-restaurant + grocery orders go
-- through the `orders` table which already has trg_enforce_app_closure.
CREATE OR REPLACE FUNCTION public.enforce_app_closure_today()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.app_is_closed_on(public.hotbite_today()) THEN
    RAISE EXCEPTION 'APP_CLOSED: HotBite is closed today (%). Please try again on an open day.',
      public.hotbite_today() USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_app_closure_master ON public.master_orders;
CREATE TRIGGER trg_enforce_app_closure_master BEFORE INSERT ON public.master_orders
  FOR EACH ROW EXECUTE FUNCTION public.enforce_app_closure_today();

NOTIFY pgrst, 'reload schema';
