-- Mirrors promo_codes.applies_to on the banner itself so the admin form can
-- display/edit the discount scope without an extra join back to promo_codes.
ALTER TABLE public.banners
  ADD COLUMN IF NOT EXISTS applies_to text CHECK (applies_to IN ('subtotal', 'delivery_fee', 'total'));
