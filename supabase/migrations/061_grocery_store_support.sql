-- Migration 061: Add grocery store support
-- Adds store_type to restaurants, grocery-specific fields to menus,
-- and a grocery_categories lookup table.

-- ── 1. Add store_type to restaurants ────────────────────────────────────────
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS store_type TEXT NOT NULL DEFAULT 'food'
    CHECK (store_type IN ('food', 'grocery', 'both'));

-- Index for filtering by store type
CREATE INDEX IF NOT EXISTS idx_restaurants_store_type
  ON public.restaurants(store_type);

-- ── 2. Add grocery-specific fields to menus ─────────────────────────────────
-- unit: e.g. 'lb', 'kg', 'each', 'pack', 'bottle'
ALTER TABLE public.menus
  ADD COLUMN IF NOT EXISTS unit TEXT,
  ADD COLUMN IF NOT EXISTS brand TEXT,
  ADD COLUMN IF NOT EXISTS weight TEXT,
  ADD COLUMN IF NOT EXISTS in_stock BOOLEAN NOT NULL DEFAULT TRUE,
  ADD COLUMN IF NOT EXISTS max_quantity INTEGER DEFAULT 99,
  ADD COLUMN IF NOT EXISTS product_type TEXT NOT NULL DEFAULT 'food'
    CHECK (product_type IN ('food', 'grocery'));

CREATE INDEX IF NOT EXISTS idx_menus_product_type
  ON public.menus(product_type);

-- ── 3. Grocery categories lookup ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.grocery_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  icon TEXT,           -- emoji or icon name
  sort_order INTEGER DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.grocery_categories ENABLE ROW LEVEL SECURITY;

-- Everyone can read categories
CREATE POLICY "public_read_grocery_categories"
  ON public.grocery_categories FOR SELECT
  USING (true);

-- Only admins can manage categories
CREATE POLICY "admin_manage_grocery_categories"
  ON public.grocery_categories FOR ALL
  USING (public.current_user_is_admin())
  WITH CHECK (public.current_user_is_admin());

-- ── 4. Seed default grocery categories ──────────────────────────────────────
INSERT INTO public.grocery_categories (name, icon, sort_order) VALUES
  ('Fruits & Vegetables', '🥬', 1),
  ('Dairy & Eggs',        '🥛', 2),
  ('Meat & Seafood',      '🥩', 3),
  ('Bakery & Bread',      '🍞', 4),
  ('Snacks & Chips',      '🍿', 5),
  ('Beverages',           '🥤', 6),
  ('Frozen Foods',        '🧊', 7),
  ('Pantry Staples',      '🫙', 8),
  ('Household',           '🧹', 9),
  ('Personal Care',       '🧴', 10),
  ('Baby Products',       '🍼', 11),
  ('Pet Supplies',        '🐾', 12)
ON CONFLICT (name) DO NOTHING;
