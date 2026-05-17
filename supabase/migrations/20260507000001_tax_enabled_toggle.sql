-- Migration: add tax_enabled toggle to app_config
-- Lets admin turn customer-facing tax on/off without changing the rate.
INSERT INTO app_config (key, value, value_type, category, description)
VALUES ('tax_enabled', '1', 'boolean', 'fees', 'Apply tax to customer order totals (1=on, 0=off)')
ON CONFLICT (key) DO NOTHING;
