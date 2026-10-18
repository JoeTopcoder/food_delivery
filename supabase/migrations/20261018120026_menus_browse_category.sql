-- Separate the home "Browse by Category" taxonomy from the per-restaurant menu
-- section. menus.category stays the restaurant's own section header (e.g.
-- "Chicken Combos", "Sandwiches", "Burgers"); browse_category holds the
-- canonical home chip (Chicken, Fast Food, Pizza, …) that Browse-by-Category
-- filters on. The auto-categorize job now writes browse_category, so it never
-- clobbers the menu sections again.
ALTER TABLE menus ADD COLUMN IF NOT EXISTS browse_category TEXT;
CREATE INDEX IF NOT EXISTS idx_menus_browse_category ON menus (browse_category);
COMMENT ON COLUMN menus.browse_category IS
  'Canonical home Browse-by-Category chip (Chicken/Fast Food/Pizza/...). Set by auto-categorize-menus. Distinct from category (the per-restaurant menu section).';
NOTIFY pgrst, 'reload schema';
