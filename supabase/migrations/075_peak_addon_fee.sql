-- Migration 075: Peak hour delivery add-on fee
-- Allows admin to charge an extra flat fee during peak hours.
-- peak_addon_fee = 0 means disabled (no extra charge).
-- peak_hours_start / peak_hours_end are 24h integers (e.g. 11, 14, 18, 21).

INSERT INTO app_config (key, value, value_type, category, description) VALUES
  ('peak_addon_fee',   '1.00', 'number', 'delivery', 'Extra flat fee added during peak hours ($). 0 = disabled.'),
  ('peak_hours_start', '11',   'number', 'delivery', 'Peak hours start (24h, e.g. 11 = 11 AM)'),
  ('peak_hours_end',   '14',   'number', 'delivery', 'Peak hours end (24h, e.g. 14 = 2 PM)'),
  ('peak_hours_start_2', '18', 'number', 'delivery', 'Evening peak start (24h, e.g. 18 = 6 PM)'),
  ('peak_hours_end_2',   '21', 'number', 'delivery', 'Evening peak end (24h, e.g. 21 = 9 PM)')
ON CONFLICT (key) DO NOTHING;
