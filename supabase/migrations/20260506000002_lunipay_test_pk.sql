-- Lunipay publishable key (pk_test) for the Flutter client.
-- Loaded into AppConstants.lunipayPublishableKey at app startup.
INSERT INTO app_config (key, value)
VALUES (
  'lunipay_publishable_key',
  '"pk_test_9bkNh0KkY850L2PyQQXiqhNfVbb6WiS4hdS4lMYA"'::jsonb
)
ON CONFLICT (key) DO UPDATE
  SET value = EXCLUDED.value,
      updated_at = now();
