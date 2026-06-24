-- ── 098_food_categories_image_url ──────────────────────────────────────────
-- Adds image_url to food_categories so the customer home screen can show
-- real photos instead of emojis.  Images are sourced from Unsplash CDN
-- (free, no API key required for display).  Admins can update these at any
-- time from the admin panel without an app release.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.food_categories
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- Seed high-quality food images for each default category.
-- Format: https://images.unsplash.com/photo-{ID}?w=200&h=200&q=80&fit=crop
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1533089860892-a7c6f0a88666?w=200&h=200&q=80&fit=crop' WHERE name = 'Breakfast';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=200&h=200&q=80&fit=crop' WHERE name = 'Fast Food';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=200&h=200&q=80&fit=crop' WHERE name = 'Pizza';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1598103442097-8b74394b95c3?w=200&h=200&q=80&fit=crop' WHERE name = 'Chicken';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1565299507177-b0ac66763828?w=200&h=200&q=80&fit=crop' WHERE name = 'Mexican';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1563245372-f21724e3856d?w=200&h=200&q=80&fit=crop' WHERE name = 'Chinese';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1579871494447-9811cf80d66c?w=200&h=200&q=80&fit=crop' WHERE name = 'Sushi';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=200&h=200&q=80&fit=crop' WHERE name = 'Healthy';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1551024506-0bccd828d307?w=200&h=200&q=80&fit=crop' WHERE name = 'Dessert';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?w=200&h=200&q=80&fit=crop' WHERE name = 'Coffee';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1544145945-f90425340c7e?w=200&h=200&q=80&fit=crop' WHERE name = 'Drinks';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1540914124281-342587941389?w=200&h=200&q=80&fit=crop' WHERE name = 'Vegan';
-- Extra categories added via admin panel
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1584278858536-52532423b5ea?w=200&h=200&q=80&fit=crop' WHERE name ILIKE '%canned%';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1582058091922-57408e8da2f3?w=200&h=200&q=80&fit=crop' WHERE name ILIKE '%confection%';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=200&h=200&q=80&fit=crop' WHERE name ILIKE '%instant%';
UPDATE public.food_categories SET image_url = 'https://images.unsplash.com/photo-1555949258-eb67b1ef0ceb?w=200&h=200&q=80&fit=crop' WHERE name ILIKE '%snack%';
