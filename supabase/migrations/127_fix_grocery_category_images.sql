-- ── 127_fix_grocery_category_images ──────────────────────────────────────────
-- Ensures every grocery_categories row has an appropriate image_url.
-- Uses very broad ILIKE patterns to tolerate typos and name variations
-- (e.g. "Caned Good" vs "Canned Goods", "Confectionery" vs "Confections").
-- All updates are UNCONDITIONAL — they overwrite whatever was there before
-- so broken / box-photo URLs are replaced too.
-- Run in Supabase Dashboard → SQL Editor.
-- ─────────────────────────────────────────────────────────────────────────────

-- Ensure column exists (safe to re-run)
ALTER TABLE public.grocery_categories
  ADD COLUMN IF NOT EXISTS image_url TEXT;

-- ── 4 categories that were showing brown box ──────────────────────────────────

-- "Caned Good", "Caned Goods", "Canned Good", "Canned Goods", or anything
-- that starts with "can" and contains "good/goods" or just "canned"/"caned"
UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1584278858536-52532423b5ea?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE 'caned%'
     OR name ILIKE 'canned%'
     OR (name ILIKE 'can%' AND name ILIKE '%good%');

-- "Confectionery", "Confections", "Confection"
UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1575377427642-087cf684f29d?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE 'confect%'
     OR name ILIKE '%candy%'
     OR name ILIKE '%sweets%'
     OR name ILIKE '%chocolat%';

-- "Instant Food", "Instant Noodles", "Instant Meal"
UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1569718212165-3a8278d5f624?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE 'instant%'
     OR (name ILIKE '%ready%' AND name ILIKE '%meal%')
     OR (name ILIKE '%noodle%' AND name NOT ILIKE '%fresh%');

-- "Snacks", "Snack", "Snacks & Chips", "Chips"
UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1566478989037-eec170784d0b?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%snack%'
     OR name ILIKE '%chip%'
     OR name ILIKE '%crisp%';

-- ── All remaining standard categories ────────────────────────────────────────

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1540420773420-3366772f4999?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%fruit%' OR name ILIKE '%vegetable%' OR name ILIKE '%produce%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%dairy%' OR name ILIKE '%egg%' OR name ILIKE '%milk%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1529692236671-f1f6cf9683ba?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%meat%' OR name ILIKE '%seafood%' OR name ILIKE '%fish%' OR name ILIKE '%chicken%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%bakery%' OR name ILIKE '%bread%' OR name ILIKE '%pastry%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1534353436294-a6c9f2c791c0?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%beverage%' OR name ILIKE '%drink%' OR name ILIKE '%juice%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1547592180-85f173990554?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%frozen%' OR name ILIKE '%ice cream%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1586201375761-83865001e31c?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%pantry%' OR name ILIKE '%staple%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%household%' OR name ILIKE '%cleaning%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1556228720-195a672e8a03?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%personal%' OR name ILIKE '%hygiene%' OR name ILIKE '%beauty%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%baby%' OR name ILIKE '%infant%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1587300003388-59208cc962cb?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%pet%' OR name ILIKE '%dog food%' OR name ILIKE '%cat food%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1517093157656-b9eccef91cb1?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%cereal%' OR name ILIKE '%breakfast%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1474979266404-7eaacbcd87c5?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%oil%' OR name ILIKE '%sauce%' OR name ILIKE '%spice%' OR name ILIKE '%condiment%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1516714435131-44d6b64dc6a2?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%rice%' OR name ILIKE '%pasta%' OR name ILIKE '%grain%';

UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=200&h=200&q=80&fit=crop'
  WHERE name ILIKE '%organic%' OR name ILIKE '%health%';

-- Catch-all: any category still with no image gets a generic grocery store photo
UPDATE public.grocery_categories
  SET image_url = 'https://images.unsplash.com/photo-1543168256-418811576931?w=200&h=200&q=80&fit=crop'
  WHERE image_url IS NULL OR image_url = '';
