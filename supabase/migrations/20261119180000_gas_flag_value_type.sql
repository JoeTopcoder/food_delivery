-- Fix: gas feature flags were inserted without value_type, so the app parsed
-- them as strings and the boolean reader fell back to false — hiding the
-- Cooking Gas launcher tile even though value='true'. Mark them boolean to match
-- the other service_* flags.
UPDATE public.app_config SET value_type='boolean'
  WHERE key IN ('service_gas_enabled','gas_enabled') AND value_type IS DISTINCT FROM 'boolean';
NOTIFY pgrst, 'reload schema';
