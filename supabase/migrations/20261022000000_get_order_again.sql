-- Authoritative server-side source for the customer "Order Again" rail.
--
-- Mirrors the client logic but enforces the rules in the database so grocery
-- orders can never surface on the food home regardless of the client:
--   * only the caller's own orders (pinned to auth.uid())
--   * only genuinely completed, reorderable orders
--   * grocery stores excluded entirely (they have their own rail/flow)
--   * one row per chain (chain_id) or standalone restaurant, ranked by how
--     often ordered, then most recent; the reorder target is the latest order.
CREATE OR REPLACE FUNCTION public.get_order_again(p_limit integer DEFAULT 8)
RETURNS TABLE(
  order_id uuid,
  restaurant_id uuid,
  group_key text,
  times_ordered bigint,
  last_ordered_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  WITH mine AS (
    SELECT
      o.id,
      o.restaurant_id,
      COALESCE(o.ordered_at, o.created_at) AS at,
      -- chain grouping key: 'c:<chain_id>' when the store belongs to a chain,
      -- else the restaurant id itself.
      COALESCE(
        NULLIF('c:' || COALESCE(r.chain_id::text, ''), 'c:'),
        o.restaurant_id::text
      ) AS gkey
    FROM orders o
    JOIN restaurants r ON r.id = o.restaurant_id
    WHERE o.user_id = auth.uid()
      AND o.status IN ('delivered', 'completed')
      AND r.store_type <> 'grocery'
  ),
  grouped AS (
    SELECT
      gkey,
      (array_agg(id ORDER BY at DESC))[1]            AS order_id,
      (array_agg(restaurant_id ORDER BY at DESC))[1] AS restaurant_id,
      count(*)                                       AS times_ordered,
      max(at)                                        AS last_ordered_at
    FROM mine
    GROUP BY gkey
  )
  SELECT order_id, restaurant_id, gkey, times_ordered, last_ordered_at
  FROM grouped
  ORDER BY times_ordered DESC, last_ordered_at DESC
  LIMIT GREATEST(p_limit, 0);
$function$;

REVOKE ALL ON FUNCTION public.get_order_again(integer) FROM public;
GRANT EXECUTE ON FUNCTION public.get_order_again(integer) TO authenticated;

NOTIFY pgrst, 'reload schema';
