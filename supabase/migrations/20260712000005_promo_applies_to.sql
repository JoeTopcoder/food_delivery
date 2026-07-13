-- ─────────────────────────────────────────────────────────────────────────────
-- Promo codes (including banner-backed ones) can now target what they
-- discount: the meal/food subtotal (default, unchanged behavior for every
-- existing code), the delivery fee, or the entire order total.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.promo_codes
  ADD COLUMN IF NOT EXISTS applies_to text NOT NULL DEFAULT 'subtotal'
    CHECK (applies_to IN ('subtotal', 'delivery_fee', 'total'));
