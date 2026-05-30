SELECT
  current_setting('app.settings.service_role_key', true) IS NOT NULL AS has_service_key,
  length(coalesce(current_setting('app.settings.service_role_key', true), '')) AS key_length;
