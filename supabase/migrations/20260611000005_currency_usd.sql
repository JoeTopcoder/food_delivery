-- Ensure app_config has USD currency and correct airport surcharge in USD
INSERT INTO app_config (key, value, value_type, description)
VALUES
  ('currency_code',   to_jsonb('USD'::text),       'string', 'ISO 4217 currency code'),
  ('currency_symbol', to_jsonb('$'::text),          'string', 'Currency symbol shown in UI'),
  ('currency_name',   to_jsonb('US Dollar'::text),  'string', 'Currency display name'),
  ('airport_surcharge_jmd', to_jsonb(10.0::text),   'number', 'Airport surcharge in USD (formerly JMD)')
ON CONFLICT (key) DO UPDATE
  SET value      = EXCLUDED.value,
      updated_at = now();
