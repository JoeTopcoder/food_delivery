-- ============================================================================
-- Migration 085: Switch delivery pricing from per-km to per-mile ($2–$2.50/mi)
-- ============================================================================

-- Add new per-mile config keys
INSERT INTO app_config (key, value, description)
VALUES
  ('delivery_per_mile_fee',      '2.0',  'Standard delivery rate per mile (USD)'),
  ('delivery_per_mile_fee_peak', '2.5',  'Peak-hour delivery rate per mile (USD)'),
  ('delivery_base_miles',        '1.0',  'Miles included in base fee before per-mile charge')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, description = EXCLUDED.description;

-- Update base fee to $3.00
UPDATE app_config SET value = '3.0', description = 'Flat base delivery fee (USD)' WHERE key = 'delivery_base_fee';

-- Update minimum fee to $3.00
UPDATE app_config SET value = '3.0', description = 'Minimum delivery fee (USD)' WHERE key = 'min_delivery_fee';
