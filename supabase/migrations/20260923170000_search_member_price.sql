-- Surface the HotBite+ member price through menu search so member pricing is
-- consistent on the search results screen (spec §18). Cast to numeric to avoid
-- the numeric-vs-double RETURNS TABLE type mismatch that has broken this RPC
-- before.
DROP FUNCTION IF EXISTS public.search_menu_items(text, text, numeric, numeric, integer);
CREATE OR REPLACE FUNCTION public.search_menu_items(
  p_query text DEFAULT NULL::text,
  p_cuisine text DEFAULT NULL::text,
  p_max_price numeric DEFAULT NULL::numeric,
  p_min_rating numeric DEFAULT NULL::numeric,
  p_limit integer DEFAULT 50)
 RETURNS TABLE(item_id uuid, item_name text, item_description text, item_price numeric, item_image_url text, item_category text, item_discount numeric, item_hotbite_plus_price numeric, restaurant_id uuid, restaurant_name text, restaurant_image text, restaurant_rating numeric, restaurant_cuisine text, rank real)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    m.id AS item_id,
    m.name AS item_name,
    m.description AS item_description,
    m.price::numeric AS item_price,
    m.image_url AS item_image_url,
    m.category AS item_category,
    m.discount::numeric AS item_discount,
    m.hotbite_plus_price::numeric AS item_hotbite_plus_price,
    r.id AS restaurant_id,
    r.name AS restaurant_name,
    r.image_url AS restaurant_image,
    r.rating::numeric AS restaurant_rating,
    r.cuisine_type AS restaurant_cuisine,
    CASE
      WHEN p_query IS NOT NULL AND p_query != '' THEN
        ts_rank(m.search_vector, plainto_tsquery('english', p_query))
      ELSE 1.0
    END::REAL AS rank
  FROM menus m
  JOIN restaurants r ON r.id = m.restaurant_id
  WHERE m.is_available = true
    AND COALESCE(m.product_type, 'food') != 'grocery'
    AND COALESCE(r.store_type, 'food') != 'grocery'
    AND (p_query IS NULL OR p_query = '' OR m.search_vector @@ plainto_tsquery('english', p_query)
         OR m.name ILIKE '%' || p_query || '%')
    AND (p_cuisine IS NULL OR r.cuisine_type ILIKE '%' || p_cuisine || '%')
    AND (p_max_price IS NULL OR m.price <= p_max_price)
    AND (p_min_rating IS NULL OR r.rating >= p_min_rating)
  ORDER BY rank DESC, m.name
  LIMIT p_limit;
END;
$function$;

NOTIFY pgrst, 'reload schema';
