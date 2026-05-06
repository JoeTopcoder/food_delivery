-- Belt-and-suspenders: also fire the apology brain when an order's
-- in-place `user_rating` is set to a low value, in case a client path
-- updates the order row without inserting into `reviews`.
CREATE OR REPLACE FUNCTION trg_low_order_rating_apology()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.user_rating IS NOT NULL
     AND NEW.user_rating <= 2
     AND (OLD.user_rating IS DISTINCT FROM NEW.user_rating)
     AND NEW.user_id IS NOT NULL
  THEN
    PERFORM public.issue_apology_coupon(
      NEW.user_id,
      'low_review',
      NEW.id,
      NEW.user_rating::numeric,
      'order rating <= 2'
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_low_order_rating_apology ON public.orders;
CREATE TRIGGER trg_low_order_rating_apology
AFTER UPDATE OF user_rating ON public.orders
FOR EACH ROW
EXECUTE FUNCTION trg_low_order_rating_apology();
