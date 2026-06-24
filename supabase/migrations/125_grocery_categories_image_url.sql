-- ── 125_grocery_categories_image_url ─────────────────────────────────────────
-- Adds image_url to grocery_categories so the grocery screen shows real
-- photos instead of emoji-only tiles.  Images from Unsplash CDN (free).
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.grocery_categories
  ADD COLUMN IF NOT EXISTS image_url TEXT;

UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=200&h=200&q=80&fit=crop' WHERE name = 'Fruits & Vegetables';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=200&h=200&q=80&fit=crop' WHERE name = 'Dairy & Eggs';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1529692236671-f1f6cf9683ba?w=200&h=200&q=80&fit=crop' WHERE name = 'Meat & Seafood';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=200&h=200&q=80&fit=crop' WHERE name = 'Bakery & Bread';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=200&h=200&q=80&fit=crop' WHERE name = 'Snacks & Chips';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1534353436294-a6c9f2c791c0?w=200&h=200&q=80&fit=crop' WHERE name = 'Beverages';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1547592180-85f173990554?w=200&h=200&q=80&fit=crop' WHERE name = 'Frozen Foods';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1586201375761-83865001e31c?w=200&h=200&q=80&fit=crop' WHERE name = 'Pantry Staples';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=200&h=200&q=80&fit=crop' WHERE name = 'Household';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1556228720-195a672e8a03?w=200&h=200&q=80&fit=crop' WHERE name = 'Personal Care';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=200&h=200&q=80&fit=crop' WHERE name = 'Baby Products';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1587300003388-59208cc962cb?w=200&h=200&q=80&fit=crop' WHERE name = 'Pet Supplies';
-- Extra categories that may have been added via admin panel
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1584278858536-52532423b5ea?w=200&h=200&q=80&fit=crop' WHERE name ILIKE '%canned%';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1582058091922-57408e8da2f3?w=200&h=200&q=80&fit=crop' WHERE name ILIKE '%confection%';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=200&h=200&q=80&fit=crop' WHERE name ILIKE '%instant%';
UPDATE public.grocery_categories SET image_url = 'https://images.unsplash.com/photo-1555949258-eb67b1ef0ceb?w=200&h=200&q=80&fit=crop' WHERE name ILIKE '%snack%';
