-- Migration: per-zone tax settings on delivery_regions
-- tax_enabled = false (default) → no tax in this zone
-- tax_rate    = NULL            → inherit global app_config tax_rate when enabled

ALTER TABLE public.delivery_regions
  ADD COLUMN IF NOT EXISTS tax_enabled BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS tax_rate    DOUBLE PRECISION DEFAULT NULL;

COMMENT ON COLUMN public.delivery_regions.tax_enabled IS
  'When true, tax is applied to orders whose delivery address falls in this zone.';
COMMENT ON COLUMN public.delivery_regions.tax_rate IS
  'Tax rate (0–1) for this zone. NULL = use global app_config tax_rate.';
