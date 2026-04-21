-- Fix infinite recursion in group_order_participants RLS policy
-- The cycle: group_orders policy checks group_order_participants,
--            group_order_participants policy checks group_orders → loop

-- Drop the recursive policies
DROP POLICY IF EXISTS group_orders_select ON group_orders;
DROP POLICY IF EXISTS group_participants_select ON group_order_participants;

-- Helper function that checks group_orders WITHOUT triggering RLS
-- (SECURITY DEFINER runs as function owner, bypassing row-level security)
CREATE OR REPLACE FUNCTION public.auth_is_group_host(p_group_order_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM group_orders
    WHERE id = p_group_order_id
      AND host_user_id = auth.uid()
  );
$$;

-- group_orders: host can see their orders; participants can see via safe helper
CREATE POLICY group_orders_select ON group_orders FOR SELECT USING (
  host_user_id = auth.uid()
  OR EXISTS (
    SELECT 1 FROM group_order_participants
    WHERE group_order_id = group_orders.id
      AND user_id = auth.uid()
  )
);

-- group_order_participants: own rows OR host of the group (via SECURITY DEFINER — no recursion)
CREATE POLICY group_participants_select ON group_order_participants FOR SELECT USING (
  user_id = auth.uid()
  OR auth_is_group_host(group_order_id)
);
