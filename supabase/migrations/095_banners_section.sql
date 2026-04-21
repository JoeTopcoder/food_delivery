-- Add section field to banners so admin can create banners specific to
-- the food home screen or the grocery section.
ALTER TABLE public.banners
  ADD COLUMN IF NOT EXISTS section TEXT NOT NULL DEFAULT 'food'
    CHECK (section IN ('food', 'grocery'));

CREATE INDEX IF NOT EXISTS idx_banners_section ON public.banners(section);
