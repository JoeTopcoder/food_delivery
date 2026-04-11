-- ====================================================================
-- MIGRATION 014: Add menu item sides / add-ons system
-- Allows restaurants to define optional or required side choices per
-- menu item, and records selected sides on each order item.
-- ====================================================================

-- 1. Side options that a restaurant can attach to a menu item
CREATE TABLE IF NOT EXISTS public.menu_item_sides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id UUID NOT NULL REFERENCES public.menus(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  price DOUBLE PRECISION NOT NULL DEFAULT 0,
  is_available BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_menu_item_sides_menu_item_id ON public.menu_item_sides(menu_item_id);

-- 2. Sides selected by a customer on an order item
CREATE TABLE IF NOT EXISTS public.order_item_sides (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_item_id UUID NOT NULL REFERENCES public.order_items(id) ON DELETE CASCADE,
  side_name TEXT NOT NULL,
  side_price DOUBLE PRECISION NOT NULL DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_order_item_sides_order_item_id ON public.order_item_sides(order_item_id);

-- 3. RLS policies for menu_item_sides
ALTER TABLE public.menu_item_sides ENABLE ROW LEVEL SECURITY;

-- Everyone can read sides
CREATE POLICY "Anyone can view menu item sides"
  ON public.menu_item_sides FOR SELECT
  USING (true);

-- Restaurant owners can manage their own sides
CREATE POLICY "Restaurant owners can insert sides"
  ON public.menu_item_sides FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.menus m
      JOIN public.restaurants r ON r.id = m.restaurant_id
      WHERE m.id = menu_item_id
        AND r.owner_id = auth.uid()
    )
  );

CREATE POLICY "Restaurant owners can update sides"
  ON public.menu_item_sides FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.menus m
      JOIN public.restaurants r ON r.id = m.restaurant_id
      WHERE m.id = menu_item_id
        AND r.owner_id = auth.uid()
    )
  );

CREATE POLICY "Restaurant owners can delete sides"
  ON public.menu_item_sides FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.menus m
      JOIN public.restaurants r ON r.id = m.restaurant_id
      WHERE m.id = menu_item_id
        AND r.owner_id = auth.uid()
    )
  );

-- 4. RLS policies for order_item_sides
ALTER TABLE public.order_item_sides ENABLE ROW LEVEL SECURITY;

-- Users can view sides on their own order items
CREATE POLICY "Users can view their order item sides"
  ON public.order_item_sides FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
      WHERE oi.id = order_item_id
        AND (o.user_id = auth.uid()
             OR EXISTS (
               SELECT 1 FROM public.restaurants r
               WHERE r.id = o.restaurant_id AND r.owner_id = auth.uid()
             ))
    )
  );

-- Users can insert sides when placing an order
CREATE POLICY "Users can insert order item sides"
  ON public.order_item_sides FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.order_items oi
      JOIN public.orders o ON o.id = oi.order_id
      WHERE oi.id = order_item_id
        AND o.user_id = auth.uid()
    )
  );
