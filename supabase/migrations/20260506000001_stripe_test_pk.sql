-- Update Stripe publishable key in runtime app_config so all clients pick it up.
INSERT INTO app_config (key, value)
VALUES (
  'stripe_publishable_key',
  '"pk_test_XKonhF8icf0oh2Ouq8y6iDCtks5FeNhvi5URu0Ga"'::jsonb
)
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value,
      updated_at = now();
