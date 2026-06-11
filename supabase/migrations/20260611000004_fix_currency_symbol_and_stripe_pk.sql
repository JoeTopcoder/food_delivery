-- Restore currency_symbol to $ (may have been overwritten accidentally).
-- Stripe live key must be set manually — see app_config table, key = 'stripe_publishable_key'.
UPDATE app_config
SET value      = to_jsonb('$'::text),
    updated_at = now()
WHERE key = 'currency_symbol';
