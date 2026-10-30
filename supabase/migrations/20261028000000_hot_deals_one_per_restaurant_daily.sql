-- Hot Deals: show at most ONE deal per restaurant (per brand/chain), and rotate
-- which item is featured each day. The pick is deterministic within a Jamaica
-- day (stable all day) but changes daily, via a date-seeded hash ordering.

CREATE OR REPLACE FUNCTION public.get_hot_deals(p_limit integer DEFAULT 12, p_grocery boolean DEFAULT false)
 RETURNS TABLE(id uuid, restaurant_id uuid, name text, image_url text, restaurant_name text, price numeric, sale_price numeric, discount numeric)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  WITH deals AS (
    SELECT m.id, m.restaurant_id, m.name, m.image_url, m.price, m.discount, m.rating,
           COALESCE(NULLIF(r.chain_id,''), r.id::text) AS grp,
           COALESCE(NULLIF(r.chain_name,''), r.name)   AS rname
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
  ),
  picked AS (
    -- one item per brand/restaurant, chosen by a per-day hash so it rotates daily
    SELECT DISTINCT ON (grp) *
    FROM deals
    ORDER BY grp,
             md5(id::text || (now() AT TIME ZONE 'America/Jamaica')::date::text)
  )
  SELECT id, restaurant_id, name, image_url, rname AS restaurant_name,
         price::numeric,
         (price * (1 - discount/100.0))::numeric AS sale_price,
         discount::numeric
  FROM picked
  ORDER BY discount DESC, rating DESC NULLS LAST
  LIMIT GREATEST(p_limit, 1);
$function$;

NOTIFY pgrst, 'reload schema';
