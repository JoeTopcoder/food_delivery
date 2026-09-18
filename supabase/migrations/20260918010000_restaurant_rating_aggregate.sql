-- Restaurant cards read restaurants.rating / review_count, but those were
-- never kept in sync with the reviews table — every restaurant showed 0 even
-- when it had real reviews. This recomputes the aggregate from reviews and
-- keeps it current via a trigger, so the rating shown on every card is right.

CREATE OR REPLACE FUNCTION public.recompute_restaurant_rating(p_restaurant_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_avg   numeric;
  v_count integer;
BEGIN
  IF p_restaurant_id IS NULL THEN
    RETURN;
  END IF;

  SELECT avg(rating), count(*)
    INTO v_avg, v_count
  FROM reviews
  WHERE restaurant_id = p_restaurant_id
    AND rating IS NOT NULL;

  UPDATE restaurants
     SET rating       = COALESCE(round(v_avg::numeric, 1), 0),
         review_count = COALESCE(v_count, 0)
   WHERE id = p_restaurant_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.trg_reviews_recompute_rating()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'DELETE' THEN
    PERFORM public.recompute_restaurant_rating(OLD.restaurant_id);
    RETURN OLD;
  END IF;

  -- On UPDATE the review may have been moved to a different restaurant.
  IF TG_OP = 'UPDATE' AND OLD.restaurant_id IS DISTINCT FROM NEW.restaurant_id THEN
    PERFORM public.recompute_restaurant_rating(OLD.restaurant_id);
  END IF;

  PERFORM public.recompute_restaurant_rating(NEW.restaurant_id);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS reviews_recompute_rating ON reviews;
CREATE TRIGGER reviews_recompute_rating
AFTER INSERT OR UPDATE OR DELETE ON reviews
FOR EACH ROW
EXECUTE FUNCTION public.trg_reviews_recompute_rating();

-- Backfill every restaurant from the reviews it already has.
UPDATE restaurants r
   SET rating       = COALESCE(round(agg.avg_rating::numeric, 1), 0),
       review_count = COALESCE(agg.n, 0)
  FROM (
    SELECT restaurant_id, avg(rating) AS avg_rating, count(*) AS n
    FROM reviews
    WHERE rating IS NOT NULL
    GROUP BY restaurant_id
  ) agg
 WHERE r.id = agg.restaurant_id;

NOTIFY pgrst, 'reload schema';
