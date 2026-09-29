-- Fix broken search RPCs: menus.price / menus.discount are double precision but
-- both functions declare numeric return columns, so they raised 42804
-- ("structure of query does not match function result type") on every call —
-- the Dart services swallowed the error, silently killing the smart-search
-- "Menu Items" tab and "Recommended for You". Cast the columns to numeric.
-- Grocery-exclusion filters are preserved unchanged.

CREATE OR REPLACE FUNCTION public.search_menu_items(
  p_query text DEFAULT NULL::text,
  p_cuisine text DEFAULT NULL::text,
  p_max_price numeric DEFAULT NULL::numeric,
  p_min_rating numeric DEFAULT NULL::numeric,
  p_limit integer DEFAULT 50
)
RETURNS TABLE(
  item_id uuid, item_name text, item_description text, item_price numeric,
  item_image_url text, item_category text, item_discount numeric,
  restaurant_id uuid, restaurant_name text, restaurant_image text,
  restaurant_rating numeric, restaurant_cuisine text, rank real
)
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

CREATE OR REPLACE FUNCTION public.get_recommendations(
  p_user_id uuid,
  p_limit integer DEFAULT 20
)
RETURNS TABLE(
  item_id uuid, item_name text, item_price numeric, item_image_url text,
  restaurant_id uuid, restaurant_name text, restaurant_image text, score real
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  WITH user_cuisines AS (
    SELECT DISTINCT r.cuisine_type
    FROM orders o
    JOIN restaurants r ON r.id = o.restaurant_id
    WHERE o.user_id = p_user_id AND o.status = 'delivered'
  ),
  user_ordered_items AS (
    SELECT DISTINCT oi.menu_item_id
    FROM order_items oi
    JOIN orders o ON o.id = oi.order_id
    WHERE o.user_id = p_user_id
  )
  SELECT
    m.id AS item_id,
    m.name AS item_name,
    m.price::numeric AS item_price,
    m.image_url AS item_image_url,
    r.id AS restaurant_id,
    r.name AS restaurant_name,
    r.image_url AS restaurant_image,
    (COALESCE(r.rating, 3.0) * 0.6 + RANDOM()::NUMERIC * 2)::REAL AS score
  FROM menus m
  JOIN restaurants r ON r.id = m.restaurant_id
  WHERE m.is_available = true
    AND r.is_open = true
    AND COALESCE(m.product_type, 'food') != 'grocery'
    AND COALESCE(r.store_type, 'food') != 'grocery'
    AND (
      r.cuisine_type IN (SELECT cuisine_type FROM user_cuisines)
      OR r.rating >= 4.0
    )
    AND m.id NOT IN (SELECT menu_item_id FROM user_ordered_items WHERE menu_item_id IS NOT NULL)
  ORDER BY score DESC
  LIMIT p_limit;
END;
$function$;

NOTIFY pgrst, 'reload schema';
