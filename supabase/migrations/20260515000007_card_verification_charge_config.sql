-- Add admin-configurable card verification charge range to app_config.
-- Admins can set the min/max charge shown in the wallet "add card" flow.

INSERT INTO app_config (key, value, value_type, category, description)
VALUES
  ('card_verification_charge_min', '0',   'number', 'payments', 'Minimum card verification charge shown to customers (in USD)'),
  ('card_verification_charge_max', '3',   'number', 'payments', 'Maximum card verification charge shown to customers (in USD)')
ON CONFLICT (key) DO NOTHING;
