-- Public restaurant reviews for the restaurant detail page. SECURITY DEFINER so
-- it can attach the reviewer's display name without granting customers direct
-- read access to the users table. Returns only review fields meant to be shown
-- publicly (rating, text, date, reviewer name) for a single restaurant.
CREATE OR REPLACE FUNCTION public.get_restaurant_reviews(
  p_restaurant_id uuid,
  p_limit integer DEFAULT 50
)
RETURNS TABLE (
  id            uuid,
  rating        double precision,
  review_text   text,
  created_at    timestamptz,
  reviewer_name text,
  response_text text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    r.id,
    r.rating,
    r.review_text,
    r.created_at,
    COALESCE(NULLIF(trim(u.name), ''), 'Customer') AS reviewer_name,
    r.response_text
  FROM reviews r
  LEFT JOIN users u ON u.id = r.user_id
  WHERE r.restaurant_id = p_restaurant_id
    AND r.rating IS NOT NULL
  ORDER BY r.created_at DESC
  LIMIT GREATEST(1, LEAST(p_limit, 200));
$$;

GRANT EXECUTE ON FUNCTION public.get_restaurant_reviews(uuid, integer) TO authenticated, anon;

NOTIFY pgrst, 'reload schema';
