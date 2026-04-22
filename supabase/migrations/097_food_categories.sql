-- ── 097_food_categories ────────────────────────────────────────────────────
-- Stores the "Browse by Category" tiles shown on the customer home screen.
-- Admin can add/remove/reorder categories without an app release.
-- ───────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.food_categories (
  id          SERIAL PRIMARY KEY,
  name        TEXT    NOT NULL,
  emoji       TEXT    NOT NULL,
  sort_order  INT     NOT NULL DEFAULT 0,
  is_active   BOOLEAN NOT NULL DEFAULT TRUE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Public read access (no auth needed to browse categories)
ALTER TABLE public.food_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read food_categories"
  ON public.food_categories FOR SELECT
  USING (is_active = TRUE);

CREATE POLICY "Only admins can modify food_categories"
  ON public.food_categories FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- ── Seed default categories ─────────────────────────────────────────────────
INSERT INTO public.food_categories (name, emoji, sort_order) VALUES
  ('Breakfast', '🍳', 1),
  ('Fast Food', '🍔', 2),
  ('Pizza',     '🍕', 3),
  ('Chicken',   '🍗', 4),
  ('Mexican',   '🌮', 5),
  ('Chinese',   '🍜', 6),
  ('Sushi',     '🍣', 7),
  ('Healthy',   '🥗', 8),
  ('Dessert',   '🍰', 9),
  ('Coffee',    '☕', 10),
  ('Drinks',    '🧋', 11),
  ('Vegan',     '🌱', 12)
ON CONFLICT DO NOTHING;
