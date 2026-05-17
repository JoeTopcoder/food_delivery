# How to Add NCB Test Keys Manually

Since the Supabase CLI version doesn't support direct SQL execution on remote databases, follow these steps to add the NCB test keys manually via the Supabase Dashboard.

## Option 1: Using Supabase Dashboard SQL Editor (Recommended)

1. **Go to Supabase Dashboard**
   - Navigate to: https://supabase.com/dashboard
   - Select your project: `support@applizonecentralja.com's Project`
   - Project Ref: `yharweliruemjexmuuxn`

2. **Open SQL Editor**
   - Click on **SQL Editor** in the left sidebar
   - Click **New query**

3. **Copy and Paste the SQL**
   Copy the following SQL and paste it into the editor:

```sql
-- NCB PowerTranz Test Keys
-- Insert or update NCB payment credentials with actual test values

INSERT INTO app_config (key, value, value_type, category, description)
VALUES
  -- NCB PowerTranz Sandbox Credentials (ACTUAL TEST VALUES)
  (
    'ncb_powertranz_id', 
    'test_powertranz_id', 
    'string', 
    'payments', 
    'PowerTranz Sandbox ID (from NCB)'
  ),
  (
    'ncb_powertranz_password', 
    'test_password', 
    'string', 
    'payments', 
    'PowerTranz Sandbox Password (from NCB)'
  ),
  (
    'ncb_merchant_id', 
    'test_merchant', 
    'string', 
    'payments', 
    'NCB Merchant ID'
  ),
  -- API Endpoint
  (
    'ncb_sandbox_api_url', 
    'https://staging.ptranz.com/api/spi', 
    'string', 
    'payments', 
    'PowerTranz Sandbox API endpoint'
  ),
  -- Return URL
  (
    'ncb_return_url', 
    'sevendash://payment-result', 
    'string', 
    'payments', 
    'Return URL after payment completion'
  ),
  -- Webhook Callback URL
  (
    'ncb_callback_url', 
    'https://yharweliruemjexmuuxn.functions.supabase.co/ncb-webhook', 
    'string', 
    'payments', 
    'Webhook callback URL for payment notifications'
  ),
  -- Ensure sandbox mode is enabled for testing
  (
    'ncb_use_sandbox', 
    '1', 
    'boolean', 
    'payments', 
    'Use sandbox API (1=sandbox, 0=production)'
  ),
  -- Ensure NCB payments are enabled
  (
    'ncb_enabled', 
    '1', 
    'boolean', 
    'payments', 
    'Enable PowerTranz/NCB payment method'
  )
ON CONFLICT (key) DO UPDATE SET 
  value = EXCLUDED.value,
  updated_at = NOW();
```

4. **Run the Query**
   - Click **Run** or press `Ctrl+Enter`
   - You should see a success message

5. **Verify the Keys**
   Run this query to verify:

```sql
SELECT key, value, category 
FROM app_config 
WHERE key LIKE 'ncb_%' 
ORDER BY key;
```

## Option 2: Using Table Editor

1. Go to **Table Editor** in Supabase Dashboard
2. Select the `app_config` table
3. Click **Insert** to add new rows or **Edit** to update existing ones
4. Add/update these rows:

| key | value | value_type | category | description |
|-----|-------|------------|----------|-------------|
| ncb_powertranz_id | test_powertranz_id | string | payments | PowerTranz Sandbox ID |
| ncb_powertranz_password | test_password | string | payments | PowerTranz Sandbox Password |
| ncb_merchant_id | test_merchant | string | payments | NCB Merchant ID |
| ncb_sandbox_api_url | https://staging.ptranz.com/api/spi | string | payments | Sandbox API endpoint |
| ncb_return_url | sevendash://payment-result | string | payments | Return URL |
| ncb_callback_url | https://yharweliruemjexmuuxn.functions.supabase.co/ncb-webhook | string | payments | Webhook callback |
| ncb_use_sandbox | 1 | boolean | payments | Use sandbox API |
| ncb_enabled | 1 | boolean | payments | Enable NCB payments |

## Option 3: Using psql (Advanced)

If you have psql installed and want to connect directly:

1. Get the connection string from Supabase Dashboard:
   - Go to **Settings** → **Database**
   - Copy the **Connection string** (URI)

2. Run the SQL file:
```bash
psql "YOUR_CONNECTION_STRING" -f seed_ncb_test_keys.sql
```

## After Adding Keys

1. **Restart the Flutter app** to ensure it picks up the changes
2. **Test a payment**:
   - Add items to cart
   - Go to checkout
   - Select "Pay with Card"
   - Enter test card details
   - Click "Pay"

## Replacing Test Keys with Real Keys

Once you get real credentials from NCB/PowerTranz:

1. Update the SQL above with real values
2. Run the updated SQL in the dashboard
3. Or update directly in the Table Editor

## Troubleshooting

If you still get "Payment record not found":

1. Verify the keys are set correctly:
```sql
SELECT key, value FROM app_config WHERE key LIKE 'ncb_%';
```

2. Check if the order exists:
```sql
SELECT id, total_amount, payment_status FROM orders WHERE id = 'YOUR_ORDER_ID';
```

3. Check if a payment record exists:
```sql
SELECT id, order_id, status FROM payments WHERE order_id = 'YOUR_ORDER_ID';
```

## Note

The test keys provided (`test_powertranz_id`, `test_password`, `test_merchant`) are NCB's sandbox test credentials. For production, you'll need to get real credentials from NCB/PowerTranz and update the configuration accordingly. Contact your NCB representative to obtain production credentials.
