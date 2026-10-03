-- ============================================================================
-- Multi-location brands. Restaurants that are the same brand (KFC Cross Roads,
-- KFC Springs, …) are grouped under one brand ("KFC"). Customers see the brand,
-- not each location; when they order, the system routes to the CLOSEST location
-- to their delivery address. Single-location restaurants are unaffected.
-- ============================================================================

ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS brand text;

-- Auto-group: a restaurant's brand = the first word of its name, but ONLY when
-- that first word is shared by 2+ restaurants (so genuine multi-location chains
-- collapse, and unique single stores keep standing alone). Excludes tiny/common
-- leading words. Admins can override per restaurant afterwards.
WITH firsts AS (
  SELECT id, name, is_mock_data,
         initcap(split_part(btrim(name), ' ', 1)) AS w
  FROM restaurants WHERE name IS NOT NULL AND btrim(name) <> ''
),
shared AS (
  SELECT w FROM firsts
  WHERE length(w) >= 3 AND lower(w) NOT IN ('the','mr','mrs','cafe','restaurant','bar','grill')
  GROUP BY w HAVING count(*) >= 2
)
UPDATE restaurants r SET brand = f.w
FROM firsts f JOIN shared s ON s.w = f.w
WHERE r.id = f.id AND (r.brand IS NULL OR r.brand = '');

-- Effective grouping key: brand when set, else the restaurant's own id (so
-- single stores are their own group).
CREATE OR REPLACE FUNCTION public.restaurant_group_key(p_id uuid)
RETURNS text LANGUAGE sql STABLE AS $$
  SELECT COALESCE(NULLIF(brand,''), id::text) FROM restaurants WHERE id = p_id;
$$;

-- Closest OPEN location of a brand to a lat/lng (haversine). Falls back to any
-- location of the brand, then to the passed restaurant id.
CREATE OR REPLACE FUNCTION public.brand_closest_location(
  p_brand text, p_lat double precision, p_lng double precision)
RETURNS uuid
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT id FROM restaurants
  WHERE brand IS NOT NULL AND brand = p_brand
  ORDER BY
    (is_open IS TRUE) DESC,
    CASE WHEN p_lat IS NOT NULL AND p_lng IS NOT NULL
              AND latitude IS NOT NULL AND longitude IS NOT NULL
      THEN 6371 * acos(LEAST(1, GREATEST(-1,
             cos(radians(p_lat))*cos(radians(latitude))*cos(radians(longitude)-radians(p_lng))
             + sin(radians(p_lat))*sin(radians(latitude)))))
      ELSE 999999 END ASC NULLS LAST
  LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.brand_closest_location(text,double precision,double precision) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.restaurant_group_key(uuid) TO authenticated, anon, service_role;

-- Given ANY location id + a delivery point, return the location that should
-- fulfil the order: the closest same-brand location, or the same id if no brand.
CREATE OR REPLACE FUNCTION public.resolve_fulfillment_store(
  p_restaurant_id uuid, p_lat double precision, p_lng double precision)
RETURNS uuid
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_brand text; v_store uuid;
BEGIN
  SELECT brand INTO v_brand FROM restaurants WHERE id = p_restaurant_id;
  IF v_brand IS NULL OR v_brand = '' THEN RETURN p_restaurant_id; END IF;
  v_store := public.brand_closest_location(v_brand, p_lat, p_lng);
  RETURN COALESCE(v_store, p_restaurant_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.resolve_fulfillment_store(uuid,double precision,double precision) TO authenticated, anon, service_role;

-- Admin override.
CREATE OR REPLACE FUNCTION public.admin_set_restaurant_brand(p_restaurant_id uuid, p_brand text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.require_admin();
  UPDATE restaurants SET brand = NULLIF(btrim(COALESCE(p_brand,'')),'') WHERE id = p_restaurant_id;
  RETURN jsonb_build_object('ok', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_restaurant_brand(uuid,text) TO authenticated;

CREATE INDEX IF NOT EXISTS idx_restaurants_brand ON public.restaurants(brand) WHERE brand IS NOT NULL;

NOTIFY pgrst, 'reload schema';
