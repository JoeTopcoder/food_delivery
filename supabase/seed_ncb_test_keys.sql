-- ====================================================================
-- NCB PowerTranz Test Keys
-- Run this to add test credentials for NCB/PowerTranz payment gateway
-- These are sandbox/test credentials for development
-- ====================================================================

-- Update PowerTranz test credentials with actual NCB test values
INSERT INTO app_config (key, value, value_type, category, description)
VALUES
  -- NCB PowerTranz Sandbox Credentials (ACTUAL TEST VALUES)
  (
    'ncb_powertranz_id', 
    'test_powertranz_id', 
    'string', 
    'payments', 
    'PowerTranz Sandbox ID (from NCB) - TEST VALUE'
  ),
  (
    'ncb_powertranz_password', 
    'test_password', 
    'string', 
    'payments', 
    'PowerTranz Sandbox Password (from NCB) - TEST VALUE'
  ),
  (
    'ncb_merchant_id', 
    'test_merchant', 
    'string', 
    'payments', 
    'NCB Merchant ID - TEST VALUE'
  ),
  -- API Base URL for sandbox
  (
    'ncb_sandbox_api_url', 
    'https://staging.ptranz.com/api/spi', 
    'string', 
    'payments', 
    'PowerTranz Sandbox API endpoint'
  ),
  -- Return URL for payment results
  (
    'ncb_return_url', 
    'sevendash://payment-result', 
    'string', 
    'payments', 
    'Return URL after payment completion'
  ),
  -- Webhook callback URL (replace YOURPROJECT with actual project ref)
  (
    'ncb_callback_url', 
    'https://yharweliruemjexmuuxn.functions.supabase.co/ncb-webhook', 
    'string', 
    'payments', 
    'Webhook callback URL for payment notifications'
  )
ON CONFLICT (key) DO UPDATE SET 
  value = EXCLUDED.value,
  updated_at = NOW();

-- Ensure sandbox mode is enabled for testing
INSERT INTO app_config (key, value, value_type, category, description)
VALUES
  ('ncb_use_sandbox', '1', 'boolean', 'payments', 'Use sandbox API (1=sandbox, 0=production) - ENABLED FOR TESTING')
ON CONFLICT (key) DO UPDATE SET 
  value = EXCLUDED.value,
  updated_at = NOW();

-- Ensure NCB payments are enabled
INSERT INTO app_config (key, value, value_type, category, description)
VALUES
  ('ncb_enabled', '1', 'boolean', 'payments', 'Enable PowerTranz/NCB payment method')
ON CONFLICT (key) DO UPDATE SET 
  value = EXCLUDED.value,
  updated_at = NOW();

-- ====================================================================
-- IMPORTANT: Replace the test values above with actual NCB-provided credentials
-- 
-- To get real credentials:
-- 1. Contact NCB/PowerTranz for sandbox API credentials
-- 2. They will provide:
--    - PowerTranz ID
--    - PowerTranz Password  
--    - Merchant ID
-- 3. Update the values above with the real credentials
--
-- For production, set ncb_use_sandbox to '0' and use production credentials
-- ====================================================================