-- Seed currency configuration keys in app_config.
-- Uses INSERT ... ON CONFLICT DO NOTHING so existing values are preserved.

INSERT INTO app_config (key, value, value_type, description)
VALUES
  ('currency_code',   'USD',       'string', 'ISO 4217 currency code used for Stripe payments'),
  ('currency_symbol', '$',         'string', 'Currency symbol displayed in the app'),
  ('currency_name',   'US Dollar', 'string', 'Human-readable currency name')
ON CONFLICT (key) DO NOTHING;
