-- ─────────────────────────────────────────────────────────────────────────────
-- Banners can now carry their own discount — e.g. a banner reading "15% off"
-- creates/updates a real promo_codes row, and the code lives on the banner
-- (banners.promo_code) so tapping it can auto-apply that discount for the
-- customer without them typing anything in.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.banners
  ADD COLUMN IF NOT EXISTS discount_type text CHECK (discount_type IN ('percentage', 'fixed')),
  ADD COLUMN IF NOT EXISTS discount_value numeric,
  ADD COLUMN IF NOT EXISTS promo_code text;
