-- ============================================================================
-- AUTO-CAPTURE ORDER CASH INTO THE OPEN SHIFT (reconciliation convenience).
--
-- When a CASH order's restaurant portion is CONFIRMED received by the restaurant
-- (restaurant_paid_from_float flips true — set by pay_restaurant_from_float on
-- delivery), auto-record it as a 'rider_cash_received' drawer movement on the
-- restaurant's open shift, linked to the order and de-duplicated.
--
-- This ONLY records a reconciliation row — it issues no refund, pays no
-- restaurant and deducts no driver float (the existing settlement already ran).
-- If there is not exactly one open shift, attribution is unknown, so nothing is
-- recorded (a cashier can still add it manually later; the unique index then
-- prevents a duplicate). Card/online payments never hit the drawer, so only
-- CASH_PAYMENT orders are captured.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.shift_autocapture_restaurant_cash()
  RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_shift uuid; v_cents bigint;
BEGIN
  -- Only when confirmed receipt just became true, for a cash restaurant payment.
  IF NEW.restaurant_paid_from_float IS NOT TRUE
     OR coalesce(OLD.restaurant_paid_from_float, false) IS TRUE THEN
    RETURN NEW;
  END IF;
  IF coalesce(NEW.restaurant_payment_method_snapshot,'') <> 'CASH_PAYMENT' THEN
    RETURN NEW;
  END IF;

  -- The drawer receives the restaurant food subtotal in cash.
  v_cents := round(coalesce(NEW.subtotal,0) * 100)::bigint;
  IF v_cents <= 0 THEN RETURN NEW; END IF;

  -- Exactly one open shift at this restaurant → attribute to it; else skip.
  SELECT id INTO v_shift FROM public.cashier_shifts
   WHERE restaurant_id = NEW.restaurant_id AND status = 'open'
   LIMIT 2;  -- LIMIT 2 so we can detect "more than one" cheaply
  IF v_shift IS NULL THEN RETURN NEW; END IF;
  IF (SELECT count(*) FROM public.cashier_shifts
      WHERE restaurant_id = NEW.restaurant_id AND status='open') <> 1 THEN
    RETURN NEW;  -- ambiguous; leave for manual entry
  END IF;

  BEGIN
    INSERT INTO public.shift_cash_movements
      (shift_id, restaurant_id, kind, amount_cents, order_id, note, created_by)
    VALUES (v_shift, NEW.restaurant_id, 'rider_cash_received', v_cents, NEW.id,
            'Auto: cash order ' || upper(substr(NEW.id::text,1,8)) || ' received from rider', NULL);
  EXCEPTION WHEN unique_violation THEN
    -- Already recorded for this order+kind — no-op.
    NULL;
  END;
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_shift_autocapture_cash ON public.orders;
CREATE TRIGGER trg_shift_autocapture_cash
  AFTER UPDATE OF restaurant_paid_from_float ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.shift_autocapture_restaurant_cash();

NOTIFY pgrst, 'reload schema';
