-- HotBite Picks — discovery/recommendation surface.
-- Backbone: an admin-curated table + read RPC, plus data-driven discovery RPCs
-- (most ordered / top rated / hot deals) computed in the DB, never in the
-- Flutter client. Reuses existing orders / order_items / restaurants / menus.
-- All read RPCs are SECURITY DEFINER and granted to anon+authenticated so they
-- expose only public, aggregate discovery data (never private analytics).

-- ── 1. Admin-curated picks ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotbite_picks (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  section       text NOT NULL,        -- e.g. 'featured','hot_deals','grocery'
  entity_type   text NOT NULL CHECK (entity_type IN
                  ('restaurant','menu_item','grocery_store','grocery_product')),
  entity_id     uuid NOT NULL,
  title         text,                 -- optional override label
  display_order integer NOT NULL DEFAULT 0,
  starts_at     timestamptz,          -- null = no start bound
  ends_at       timestamptz,          -- null = no end bound
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid
);

CREATE INDEX IF NOT EXISTS idx_hotbite_picks_lookup
  ON public.hotbite_picks (section, is_active, display_order);

ALTER TABLE public.hotbite_picks ENABLE ROW LEVEL SECURITY;

-- Public may read only picks that are active and within their time window.
DROP POLICY IF EXISTS hotbite_picks_public_read ON public.hotbite_picks;
CREATE POLICY hotbite_picks_public_read ON public.hotbite_picks
  FOR SELECT USING (
    is_active = true
    AND (starts_at IS NULL OR starts_at <= now())
    AND (ends_at   IS NULL OR ends_at   >= now())
  );

-- Admins manage everything.
DROP POLICY IF EXISTS hotbite_picks_admin_all ON public.hotbite_picks;
CREATE POLICY hotbite_picks_admin_all ON public.hotbite_picks
  FOR ALL USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── 2. Curated read RPC — resolves each pick to its live entity ────────────
-- Only returns entities that are still available (restaurant open+verified;
-- menu item available). Unavailable curated picks silently drop out.
CREATE OR REPLACE FUNCTION public.get_hotbite_picks(p_section text DEFAULT NULL)
RETURNS TABLE (
  pick_id       uuid,
  section       text,
  entity_type   text,
  entity_id     uuid,
  name          text,
  image_url     text,
  subtitle      text,
  price         numeric,
  sale_price    numeric,
  rating        numeric,
  review_count  integer,
  display_order integer
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
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
    -- availability guard
    AND (
      (p.entity_type IN ('restaurant','grocery_store')
         AND r.id IS NOT NULL AND COALESCE(r.is_verified,false)
         AND COALESCE(r.is_open,true))
      OR
      (p.entity_type IN ('menu_item','grocery_product')
         AND m.id IS NOT NULL AND COALESCE(m.is_available,true))
    )
  ORDER BY p.section, p.display_order, p.created_at;
$fn$;

-- ── 3. Most Ordered — real completed orders in a recent window ─────────────
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
  SELECT r.id, r.name, r.image_url, r.cuisine_type, r.rating, r.review_count,
         count(o.id) AS order_count
  FROM public.orders o
  JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.status IN ('delivered','completed')
    AND COALESCE(o.is_mock_data, false) = false
    AND COALESCE(o.notes, '') NOT ILIKE '%TEST%'
    AND o.created_at > now() - make_interval(days => GREATEST(p_days, 1))
    AND COALESCE(r.is_verified, false) = true
    AND COALESCE(r.is_open, true) = true
    AND COALESCE(r.store_type,'food') <> 'grocery'
  GROUP BY r.id, r.name, r.image_url, r.cuisine_type, r.rating, r.review_count
  ORDER BY order_count DESC, r.rating DESC NULLS LAST
  LIMIT GREATEST(p_limit, 1);
$fn$;

-- ── 4. Top Rated — with a minimum review threshold ────────────────────────
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
  SELECT r.id, r.name, r.image_url, r.cuisine_type, r.rating, r.review_count
  FROM public.restaurants r
  WHERE COALESCE(r.review_count, 0) >= GREATEST(p_min_reviews, 1)
    AND COALESCE(r.is_verified, false) = true
    AND COALESCE(r.is_open, true) = true
    AND COALESCE(r.store_type,'food') <> 'grocery'
    AND r.rating IS NOT NULL
  ORDER BY r.rating DESC, r.review_count DESC
  LIMIT GREATEST(p_limit, 1);
$fn$;

-- ── 5. Hot Deals — real active discounts from the menus table ──────────────
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
  SELECT m.id, m.restaurant_id, m.name, m.image_url, r.name AS restaurant_name,
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

-- ── 6. Admin write RPC ────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_upsert_hotbite_pick(
  p_id            uuid,
  p_section       text,
  p_entity_type   text,
  p_entity_id     uuid,
  p_title         text DEFAULT NULL,
  p_display_order integer DEFAULT 0,
  p_starts_at     timestamptz DEFAULT NULL,
  p_ends_at       timestamptz DEFAULT NULL,
  p_is_active     boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF p_id IS NULL THEN
    INSERT INTO public.hotbite_picks
      (section, entity_type, entity_id, title, display_order,
       starts_at, ends_at, is_active, created_by)
    VALUES
      (p_section, p_entity_type, p_entity_id, p_title, p_display_order,
       p_starts_at, p_ends_at, p_is_active, auth.uid())
    RETURNING id INTO v_id;
  ELSE
    UPDATE public.hotbite_picks SET
      section = p_section, entity_type = p_entity_type, entity_id = p_entity_id,
      title = p_title, display_order = p_display_order,
      starts_at = p_starts_at, ends_at = p_ends_at, is_active = p_is_active
    WHERE id = p_id
    RETURNING id INTO v_id;
  END IF;
  RETURN v_id;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.get_hotbite_picks(text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_most_ordered_restaurants(integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_top_rated_restaurants(integer, integer) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_hot_deals(integer, boolean) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_upsert_hotbite_pick(
  uuid, text, text, uuid, text, integer, timestamptz, timestamptz, boolean)
  TO authenticated;

NOTIFY pgrst, 'reload schema';
