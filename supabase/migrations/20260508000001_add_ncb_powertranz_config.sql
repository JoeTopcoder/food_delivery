-- Migration: Add PowerTranz/NCB Direct API configuration
-- Stores credentials and endpoint URLs for direct payment integration

INSERT INTO app_config (key, value, value_type, category, description)
VALUES
  -- API Endpoints
  ('ncb_sandbox_api_url', 'https://staging.ptranz.com/api/spi', 'string', 'payments', 'PowerTranz Sandbox API endpoint'),
  ('ncb_production_api_url', 'https://ptranz.com/api/spi', 'string', 'payments', 'PowerTranz Production API endpoint'),
  
  -- Settings
  ('ncb_enabled', '1', 'boolean', 'payments', 'Enable PowerTranz/NCB payment method'),
  ('ncb_fee_percent', '2.5', 'number', 'fees', 'PowerTranz transaction fee %'),
  ('ncb_use_sandbox', '1', 'boolean', 'payments', 'Use sandbox API (1=sandbox, 0=production)'),
  
  -- Return and Callback URLs
  ('ncb_return_url', 'sevendash://payment-result', 'string', 'payments', 'Return URL after payment completion'),
  ('ncb_callback_url', 'https://yharweliruemjexmuuxn.functions.supabase.co/ncb-webhook', 'string', 'payments', 'Webhook callback URL for payment notifications'),
  
  -- Credentials - NCB Test Environment Values
  -- Get test credentials from NCB/PowerTranz developer portal
  ('ncb_powertranz_id', 'test_powertranz_id', 'string', 'payments', 'PowerTranz Sandbox ID (from NCB)'),
  ('ncb_powertranz_password', 'test_password', 'string', 'payments', 'PowerTranz Sandbox Password (from NCB)'),
  ('ncb_merchant_id', 'test_merchant', 'string', 'payments', 'NCB Merchant ID')
ON CONFLICT (key) DO NOTHING;
