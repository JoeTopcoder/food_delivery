-- ─────────────────────────────────────────────────────────────────────────────
-- "Talk to Order" — derive a customer's real "usual" item(s) from actual order
-- history. No guessing: purely a frequency aggregation over order_items/orders,
-- optionally scoped to one restaurant and/or one day of week (e.g. "my Friday
-- usual from Island Grill"). Used by the ai-voice-assistant edge function when
-- a customer says "my usual" / "what I normally order".
--
-- Schema confirmed from supabase/schema.sql:
--   order_items(order_id, menu_item_id -> menus(id), item_name, price, quantity)
--   orders(user_id, restaurant_id, ordered_at, status)
-- Excludes only 'cancelled' orders (not restricted to 'delivered') so "usual"
-- reflects general ordering pattern, not just completed deliveries.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.get_usual_order_items(
  p_user_id       uuid,
  p_restaurant_id uuid DEFAULT NULL,
  p_day_of_week   int  DEFAULT NULL,  -- 0=Sunday..6=Saturday, matches Postgres EXTRACT(DOW)
  p_limit         int  DEFAULT 5
)
RETURNS TABLE (
  menu_item_id    uuid,
  item_name       text,
  restaurant_id   uuid,
  restaurant_name text,
  order_count     bigint,
  avg_price       numeric,
  last_ordered_at timestamptz
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    oi.menu_item_id,
    oi.item_name,
    o.restaurant_id,
    r.name AS restaurant_name,
    COUNT(*)              AS order_count,
    AVG(oi.price)          AS avg_price,
    MAX(o.ordered_at)      AS last_ordered_at
  FROM public.order_items oi
  JOIN public.orders o      ON o.id = oi.order_id
  JOIN public.restaurants r ON r.id = o.restaurant_id
  WHERE o.user_id = p_user_id
    AND o.status <> 'cancelled'
    AND (p_restaurant_id IS NULL OR o.restaurant_id = p_restaurant_id)
    AND (p_day_of_week IS NULL OR EXTRACT(DOW FROM o.ordered_at) = p_day_of_week)
  GROUP BY oi.menu_item_id, oi.item_name, o.restaurant_id, r.name
  ORDER BY order_count DESC, last_ordered_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.get_usual_order_items(uuid, uuid, int, int) TO service_role;
