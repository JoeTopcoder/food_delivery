-- When an order is placed (or updated) with a promo_code that belongs to a
-- user_coupons row owned by the order's customer, mark that coupon as used.
-- This makes the home apology banner disappear automatically after redemption.
CREATE OR REPLACE FUNCTION trg_mark_user_coupon_used()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $func$
BEGIN
  IF NEW.promo_code IS NOT NULL
     AND NEW.user_id IS NOT NULL
     AND length(trim(NEW.promo_code)) > 0
  THEN
    UPDATE public.user_coupons
       SET is_used = true
     WHERE user_id = NEW.user_id
       AND upper(code) = upper(NEW.promo_code)
       AND is_used = false;
  END IF;
  RETURN NEW;
END;
$func$;

DROP TRIGGER IF EXISTS trg_mark_user_coupon_used_ins ON public.orders;
CREATE TRIGGER trg_mark_user_coupon_used_ins
AFTER INSERT ON public.orders
FOR EACH ROW
EXECUTE FUNCTION trg_mark_user_coupon_used();

DROP TRIGGER IF EXISTS trg_mark_user_coupon_used_upd ON public.orders;
CREATE TRIGGER trg_mark_user_coupon_used_upd
AFTER UPDATE OF promo_code ON public.orders
FOR EACH ROW
WHEN (NEW.promo_code IS DISTINCT FROM OLD.promo_code)
EXECUTE FUNCTION trg_mark_user_coupon_used();
