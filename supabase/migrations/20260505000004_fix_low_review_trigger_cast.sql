-- Cast NEW.rating (double precision) to numeric so the function signature
-- public.issue_apology_coupon(uuid, text, uuid, numeric, text) matches.
CREATE OR REPLACE FUNCTION trg_low_review_apology()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $func$
BEGIN
  IF NEW.rating IS NOT NULL AND NEW.rating <= 2 AND NEW.user_id IS NOT NULL THEN
    PERFORM public.issue_apology_coupon(
      NEW.user_id,
      'low_review'::text,
      NEW.order_id,
      NEW.rating::numeric,
      left(coalesce(NEW.review_text, ''), 200)
    );
  END IF;
  RETURN NEW;
END;
$func$;
