-- Check if service_role_key is set
SELECT
  current_setting('app.settings.service_role_key', true) IS NOT NULL AS has_service_key,
  length(coalesce(current_setting('app.settings.service_role_key', true), '')) AS key_length;

-- Check FCM token for the test user
SELECT id, fcm_token IS NOT NULL AS has_fcm_token, length(fcm_token) AS token_length
FROM public.users
WHERE id = '41965f15-56f2-40b5-bc18-705915beafb3';

-- Check pg_net response table columns
SELECT column_name FROM information_schema.columns
WHERE table_schema = 'net' AND table_name = '_http_response'
ORDER BY ordinal_position;
