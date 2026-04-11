-- Migration 027: App Configuration Table + Centralized Settings
-- Moves all hardcoded business values into a single database-driven config table.
-- Each row is a key-value pair with a category for easy querying.

CREATE TABLE IF NOT EXISTS app_config (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL,
  value_type TEXT NOT NULL DEFAULT 'string',  -- string | number | boolean | json
  category   TEXT NOT NULL DEFAULT 'general',
  description TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Enable RLS (read-only for anon/authenticated, write for service_role)
ALTER TABLE app_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY app_config_select ON app_config FOR SELECT USING (true);

-- ── Business Constants ───────────────────────────────────────────────────────
INSERT INTO app_config (key, value, value_type, category, description) VALUES
  -- Tax & Fees
  ('tax_rate',              '0.10',   'number',  'fees',    'Tax rate applied to subtotal (10%)'),
  ('default_delivery_fee',  '50.0',   'number',  'fees',    'Default flat delivery fee in JMD'),
  ('driver_fee_per_delivery','50.0',  'number',  'fees',    'Base driver pay per delivery in JMD'),
  ('card_fee_percent',      '2.5',    'number',  'fees',    'Credit/debit card processing fee %'),
  ('bank_transfer_fee_percent','1.0', 'number',  'fees',    'Bank transfer processing fee %'),
  ('cash_fee_percent',      '0',      'number',  'fees',    'Cash payment fee %'),

  -- Delivery Fee Calculation (distance-based)
  ('delivery_base_fee',     '50.0',   'number',  'delivery','Base delivery fee in JMD'),
  ('delivery_per_km_fee',   '30.0',   'number',  'delivery','Fee per km beyond base distance'),
  ('delivery_base_km',      '3.0',    'number',  'delivery','Base distance included in base fee (km)'),
  ('delivery_max_km',       '25.0',   'number',  'delivery','Maximum delivery distance in km'),
  ('delivery_surge_multiplier','1.0', 'number',  'delivery','Surge pricing multiplier (1.0 = none)'),

  -- Loyalty Program
  ('loyalty_point_value',             '0.10',  'number',  'loyalty', 'JMD value of 1 loyalty point'),
  ('loyalty_max_redemption_percent',  '0.20',  'number',  'loyalty', 'Max % of order redeemable with points'),
  ('loyalty_points_per_100',          '10',    'number',  'loyalty', 'Points earned per JMD$100 spent'),
  ('loyalty_tier_bronze_threshold',   '0',     'number',  'loyalty', 'Points needed for Bronze tier'),
  ('loyalty_tier_silver_threshold',   '500',   'number',  'loyalty', 'Points needed for Silver tier'),
  ('loyalty_tier_gold_threshold',     '2000',  'number',  'loyalty', 'Points needed for Gold tier'),
  ('loyalty_tier_platinum_threshold', '5000',  'number',  'loyalty', 'Points needed for Platinum tier'),
  ('loyalty_multiplier_bronze',       '1.0',   'number',  'loyalty', 'Point multiplier for Bronze tier'),
  ('loyalty_multiplier_silver',       '1.25',  'number',  'loyalty', 'Point multiplier for Silver tier'),
  ('loyalty_multiplier_gold',         '1.5',   'number',  'loyalty', 'Point multiplier for Gold tier'),
  ('loyalty_multiplier_platinum',     '2.0',   'number',  'loyalty', 'Point multiplier for Platinum tier'),

  -- Commission
  ('default_commission_rate',  '0.15', 'number',  'commission', 'Default restaurant commission rate (15%)'),

  -- Tips
  ('preset_tips',  '[50,100,200,500]', 'json', 'tips', 'Preset tip amounts shown at checkout'),

  -- Timeouts & Limits
  ('api_timeout',          '30',  'number',  'system', 'API timeout in seconds'),
  ('connection_timeout',   '10',  'number',  'system', 'Connection timeout in seconds'),
  ('page_size',            '20',  'number',  'system', 'Default pagination page size'),
  ('order_assignment_cutoff_minutes', '30', 'number', 'system', 'Minutes before unassigned orders become visible to all drivers')

ON CONFLICT (key) DO NOTHING;

-- ── Helper function: get typed config value ──────────────────────────────────
CREATE OR REPLACE FUNCTION get_config(p_key TEXT, p_default TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT COALESCE(
    (SELECT value FROM app_config WHERE key = p_key),
    p_default
  );
$$;

CREATE OR REPLACE FUNCTION get_config_number(p_key TEXT, p_default DOUBLE PRECISION DEFAULT 0)
RETURNS DOUBLE PRECISION
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
  SELECT COALESCE(
    (SELECT value::DOUBLE PRECISION FROM app_config WHERE key = p_key),
    p_default
  );
$$;
