-- Migration: customer habits for the Concierge
--
-- The concierge should lean on what a customer actually orders rather than
-- treating every request as if they had never used the app. Two sources, and
-- they are deliberately weighted differently:
--
--   * order_items from real orders — they paid for it, so it counts double.
--   * concierge_cart_drafts that reached 'consumed' — they accepted the
--     basket the concierge built, which is a real signal even though it is
--     not proof of purchase.
--
-- Scoped by store_type, because a customer's grocery habits say nothing about
-- what they want for dinner out, and vice versa.

CREATE OR REPLACE FUNCTION public.get_customer_habits(
  p_user_id    UUID,
  p_store_type TEXT DEFAULT 'food',
  p_limit      INT  DEFAULT 12
)
RETURNS TABLE (
  menu_item_id  UUID,
  item_name     TEXT,
  restaurant_id UUID,
  store_name    TEXT,
  price         DOUBLE PRECISION,
  times_ordered BIGINT,
  last_ordered  TIMESTAMPTZ
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH store_scope AS (
    SELECT id FROM public.restaurants
    WHERE is_verified
      AND store_type = ANY (
        CASE WHEN p_store_type = 'grocery'
             THEN ARRAY['grocery','both'] ELSE ARRAY['food','both'] END
      )
  ),
  purchased AS (
    -- Real money changed hands: weight 2.
    SELECT oi.menu_item_id, 2::BIGINT AS weight, o.created_at
    FROM public.order_items oi
    JOIN public.orders o ON o.id = oi.order_id
    WHERE o.user_id = p_user_id
      AND oi.menu_item_id IS NOT NULL
      AND o.restaurant_id IN (SELECT id FROM store_scope)
  ),
  accepted AS (
    -- Accepted a concierge basket: weight 1.
    SELECT (li->>'item_id')::UUID AS menu_item_id, 1::BIGINT AS weight, d.created_at
    FROM public.concierge_cart_drafts d
    JOIN LATERAL jsonb_array_elements(d.line_items) li ON true
    WHERE d.user_id = p_user_id
      AND d.status = 'consumed'
      AND d.restaurant_id IN (SELECT id FROM store_scope)
      AND (li->>'item_id') ~ '^[0-9a-f-]{36}$'
  ),
  combined AS (
    SELECT * FROM purchased UNION ALL SELECT * FROM accepted
  )
  SELECT m.id, m.name, m.restaurant_id, r.name, m.price,
         SUM(c.weight) AS times_ordered,
         MAX(c.created_at) AS last_ordered
  FROM combined c
  JOIN public.menus m ON m.id = c.menu_item_id
  JOIN public.restaurants r ON r.id = m.restaurant_id
  WHERE m.is_available
  GROUP BY m.id, m.name, m.restaurant_id, r.name, m.price
  ORDER BY SUM(c.weight) DESC, MAX(c.created_at) DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.get_customer_habits TO authenticated;

NOTIFY pgrst, 'reload schema';
