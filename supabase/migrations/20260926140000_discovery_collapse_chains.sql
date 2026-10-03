-- Collapse multi-location chains into a single card in the discovery RPCs, so
-- "KFC" appears once (not "KFC Springs" + "KFC Cross Roads" …). Grouping key is
-- restaurants.chain_id (falling back to the row id for single-location stores);
-- the display name is chain_name when present. A representative id is kept so
-- the card still opens a real menu; order-time routing (resolve_fulfillment_store)
-- sends the order to the closest location to the delivery address.

-- ── Most Ordered — aggregate order counts across all of a chain's locations ──
CREATE OR REPLACE FUNCTION public.get_most_ordered_restaurants(
  p_days  integer DEFAULT 30,
  p_limit integer DEFAULT 10
)
RETURNS TABLE (
  id uuid, name text, image_url text, cuisine_type text,
  rating numeric, review_count integer, order_count bigint
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  WITH base AS (
    SELECT r.id, r.name, r.image_url, r.cuisine_type, r.rating, r.review_count,
           COALESCE(NULLIF(r.chain_id, ''), r.id::text) AS grp,
           r.chain_name,
           count(o.id) AS oc
    FROM public.orders o
    JOIN public.restaurants r ON r.id = o.restaurant_id
    WHERE o.status IN ('delivered','completed')
      AND COALESCE(o.is_mock_data, false) = false
      AND COALESCE(o.notes, '') NOT ILIKE '%TEST%'
      AND o.created_at > now() - make_interval(days => GREATEST(p_days, 1))
      AND COALESCE(r.is_verified, false) = true
      AND COALESCE(r.is_open, true) = true
      AND COALESCE(r.store_type,'food') <> 'grocery'
    GROUP BY r.id, r.name, r.image_url, r.cuisine_type, r.rating,
             r.review_count, r.chain_id, r.chain_name
  ),
  grp_tot AS (
    SELECT grp, sum(oc) AS total_oc FROM base GROUP BY grp
  ),
  rep AS (
    SELECT DISTINCT ON (grp)
           grp, id, name, image_url, cuisine_type, rating, review_count, chain_name
    FROM base
    ORDER BY grp, oc DESC, rating DESC NULLS LAST
  )
  SELECT rep.id,
         COALESCE(NULLIF(rep.chain_name, ''), rep.name) AS name,
         rep.image_url, rep.cuisine_type, rep.rating, rep.review_count,
         grp_tot.total_oc AS order_count
  FROM rep JOIN grp_tot USING (grp)
  ORDER BY order_count DESC, rep.rating DESC NULLS LAST
  LIMIT GREATEST(p_limit, 1);
$fn$;

-- ── Top Rated — one card per chain (representative = highest-rated location) ──
CREATE OR REPLACE FUNCTION public.get_top_rated_restaurants(
  p_min_reviews integer DEFAULT 3,
  p_limit       integer DEFAULT 10
)
RETURNS TABLE (
  id uuid, name text, image_url text, cuisine_type text,
  rating numeric, review_count integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  WITH base AS (
    SELECT r.id, r.name, r.image_url, r.cuisine_type, r.rating, r.review_count,
           COALESCE(NULLIF(r.chain_id, ''), r.id::text) AS grp,
           r.chain_name
    FROM public.restaurants r
    WHERE COALESCE(r.review_count, 0) >= GREATEST(p_min_reviews, 1)
      AND COALESCE(r.is_verified, false) = true
      AND COALESCE(r.is_open, true) = true
      AND COALESCE(r.store_type,'food') <> 'grocery'
      AND r.rating IS NOT NULL
  ),
  rep AS (
    SELECT DISTINCT ON (grp)
           grp, id, name, image_url, cuisine_type, rating, review_count, chain_name
    FROM base
    ORDER BY grp, rating DESC, review_count DESC
  )
  SELECT rep.id,
         COALESCE(NULLIF(rep.chain_name, ''), rep.name) AS name,
         rep.image_url, rep.cuisine_type, rep.rating, rep.review_count
  FROM rep
  ORDER BY rep.rating DESC, rep.review_count DESC
  LIMIT GREATEST(p_limit, 1);
$fn$;

-- ── Hot Deals — show the chain/brand name, not the specific location ─────────
CREATE OR REPLACE FUNCTION public.get_hot_deals(
  p_limit    integer DEFAULT 12,
  p_grocery  boolean DEFAULT false
)
RETURNS TABLE (
  id uuid, restaurant_id uuid, name text, image_url text,
  restaurant_name text, price numeric, sale_price numeric, discount numeric
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT m.id, m.restaurant_id, m.name, m.image_url,
         COALESCE(NULLIF(r.chain_name, ''), r.name) AS restaurant_name,
         m.price::numeric,
         (m.price * (1 - m.discount/100.0))::numeric AS sale_price,
         m.discount::numeric
  FROM public.menus m
  JOIN public.restaurants r ON r.id = m.restaurant_id
  WHERE COALESCE(m.discount, 0) > 0
    AND COALESCE(m.is_available, true) = true
    AND COALESCE(r.is_verified, false) = true
    AND COALESCE(r.is_open, true) = true
    AND (
      (p_grocery = true  AND (COALESCE(r.store_type,'food')='grocery' OR m.product_type='grocery'))
      OR
      (p_grocery = false AND COALESCE(r.store_type,'food')<>'grocery' AND COALESCE(m.product_type,'food')<>'grocery')
    )
  ORDER BY m.discount DESC, m.rating DESC NULLS LAST
  LIMIT GREATEST(p_limit, 1);
$fn$;

-- ── HotBite Now — one card per chain (nearest branch), branded name ──────────
CREATE OR REPLACE FUNCTION public.get_hotbite_now_restaurants(
  p_lat        double precision DEFAULT NULL,
  p_lng        double precision DEFAULT NULL,
  p_radius_km  double precision DEFAULT 10.0,
  p_limit      integer          DEFAULT 20
)
RETURNS TABLE (
  id                       uuid,
  name                     text,
  image_url                text,
  cuisine_type             text,
  rating                   numeric,
  review_count             integer,
  estimated_delivery_time  integer,
  hotbite_now_prep_minutes integer,
  avg_prep_minutes         numeric,
  distance_km              double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  WITH base AS (
    SELECT
      r.id, r.name, r.image_url, r.cuisine_type, r.rating, r.review_count,
      r.estimated_delivery_time, r.hotbite_now_prep_minutes,
      public.hotbite_now_avg_prep_minutes(r.id) AS avg_prep_minutes,
      CASE
        WHEN p_lat IS NULL OR p_lng IS NULL
             OR r.latitude IS NULL OR r.longitude IS NULL THEN NULL
        ELSE 6371.0 * 2 * asin(sqrt(
          power(sin(radians(r.latitude - p_lat) / 2), 2) +
          cos(radians(p_lat)) * cos(radians(r.latitude)) *
          power(sin(radians(r.longitude - p_lng) / 2), 2)
        ))
      END AS distance_km,
      COALESCE(NULLIF(r.chain_id, ''), r.id::text) AS grp,
      r.chain_name
    FROM public.restaurants r
    WHERE r.hotbite_now_enabled = true
      AND COALESCE(r.is_open, true) = true
      AND COALESCE(r.is_verified, false) = true
      AND COALESCE(r.store_type, 'food') <> 'grocery'
      AND EXISTS (
        SELECT 1 FROM public.menus m
        WHERE m.restaurant_id = r.id
          AND COALESCE(m.is_available, true) = true
      )
  ),
  in_range AS (
    SELECT * FROM base
    WHERE distance_km IS NULL OR distance_km <= p_radius_km
  ),
  rep AS (
    SELECT DISTINCT ON (grp) *
    FROM in_range
    ORDER BY grp, distance_km ASC NULLS LAST, hotbite_now_prep_minutes ASC
  )
  SELECT rep.id,
         COALESCE(NULLIF(rep.chain_name, ''), rep.name) AS name,
         rep.image_url, rep.cuisine_type, rep.rating, rep.review_count,
         rep.estimated_delivery_time, rep.hotbite_now_prep_minutes,
         rep.avg_prep_minutes, rep.distance_km
  FROM rep
  ORDER BY rep.hotbite_now_prep_minutes ASC, rep.rating DESC NULLS LAST
  LIMIT GREATEST(p_limit, 1);
$fn$;

GRANT EXECUTE ON FUNCTION public.get_hotbite_now_restaurants(
  double precision, double precision, double precision, integer) TO authenticated, anon;

NOTIFY pgrst, 'reload schema';
