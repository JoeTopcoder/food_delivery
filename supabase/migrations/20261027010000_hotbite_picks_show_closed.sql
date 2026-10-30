-- HotBite Picks: admin-curated picks should DISPLAY even when the store is
-- temporarily closed (ordering is still gated on the restaurant screen). The
-- old guard required is_open, so the whole rail vanished whenever the curated
-- stores were closed (e.g. overnight), leaving a "coming soon" state.
-- New guard: verified + active (not deactivated), regardless of open/closed.

CREATE OR REPLACE FUNCTION public.get_hotbite_picks(p_section text DEFAULT NULL::text)
 RETURNS TABLE(pick_id uuid, section text, entity_type text, entity_id uuid, name text, image_url text, subtitle text, price numeric, sale_price numeric, rating numeric, review_count integer, display_order integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT
    p.id, p.section, p.entity_type, p.entity_id,
    COALESCE(p.title,
      CASE WHEN p.entity_type IN ('restaurant','grocery_store') THEN r.name
           ELSE m.name END) AS name,
    CASE WHEN p.entity_type IN ('restaurant','grocery_store') THEN r.image_url
         ELSE m.image_url END AS image_url,
    CASE WHEN p.entity_type IN ('restaurant','grocery_store') THEN r.cuisine_type
         ELSE m.category END AS subtitle,
    m.price::numeric AS price,
    CASE WHEN COALESCE(m.discount,0) > 0
         THEN (m.price * (1 - m.discount/100.0))::numeric ELSE NULL END AS sale_price,
    CASE WHEN p.entity_type IN ('restaurant','grocery_store') THEN r.rating
         ELSE m.rating END AS rating,
    CASE WHEN p.entity_type IN ('restaurant','grocery_store') THEN r.review_count
         ELSE m.review_count END AS review_count,
    p.display_order
  FROM public.hotbite_picks p
  LEFT JOIN public.restaurants r
    ON p.entity_type IN ('restaurant','grocery_store') AND r.id = p.entity_id
  LEFT JOIN public.menus m
    ON p.entity_type IN ('menu_item','grocery_product') AND m.id = p.entity_id
  WHERE p.is_active = true
    AND (p.starts_at IS NULL OR p.starts_at <= now())
    AND (p.ends_at   IS NULL OR p.ends_at   >= now())
    AND (p_section IS NULL OR p.section = p_section)
    -- availability guard: curated picks show while the store is verified &
    -- active, even if temporarily closed (ordering is gated elsewhere).
    AND (
      (p.entity_type IN ('restaurant','grocery_store')
         AND r.id IS NOT NULL AND COALESCE(r.is_verified,false)
         AND COALESCE(r.is_active,true))
      OR
      (p.entity_type IN ('menu_item','grocery_product')
         AND m.id IS NOT NULL AND COALESCE(m.is_available,true))
    )
  ORDER BY p.section, p.display_order, p.created_at;
$function$;

NOTIFY pgrst, 'reload schema';
