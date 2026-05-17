# NCB PowerTranz Test Keys Setup Guide

This guide explains how to configure NCB/PowerTranz payment gateway credentials for testing.

## Overview

The payment system uses PowerTranz Direct API via NCB (National Commercial Bank) for processing card payments. The credentials are stored securely in the Supabase `app_config` table and accessed by the edge functions.

## Files Created/Modified

1. **Migration File**: `supabase/migrations/20260508000001_add_ncb_powertranz_config.sql`
   - Adds configuration keys to the database
   - Includes test placeholder credentials

2. **Seed Script**: `supabase/seed_ncb_test_keys.sql`
   - SQL script to update/add test credentials
   - Can be run independently to update keys

3. **Setup Script**: `supabase/setup_ncb_keys.ps1`
   - PowerShell script to help run the SQL
   - Provides instructions and validation

## Configuration Keys

The following keys are stored in the `app_config` table:

| Key | Description | Example Value |
|-----|-------------|---------------|
| `ncb_powertranz_id` | PowerTranz API ID | `TEST_PT_ID_12345` |
| `ncb_powertranz_password` | PowerTranz API Password | `test_password_abc123` |
| `ncb_merchant_id` | NCB Merchant ID | `TEST_MERCHANT_001` |
| `ncb_use_sandbox` | Use sandbox (1) or production (0) | `1` |
| `ncb_enabled` | Enable NCB payments | `1` |
| `ncb_sandbox_api_url` | Sandbox endpoint | `https://staging.ptranz.com/api/spi` |
| `ncb_production_api_url` | Production endpoint | `https://ptranz.com/api/spi` |
| `ncb_fee_percent` | Transaction fee percentage | `2.5` |

## Setup Instructions

### Option 1: Using the Migration (Automatic)

When you run Supabase migrations, the test keys are automatically added:

```bash
npx supabase db push
# or
npx supabase migration up
```

### Option 2: Using the Seed Script (Manual)

If you need to update or add keys manually:

```bash
# Navigate to supabase directory
cd supabase

# Run the seed script
npx supabase db execute --file seed_ncb_test_keys.sql
```

### Option 3: Direct SQL (Advanced)

You can also run SQL directly in the Supabase dashboard:

1. Go to your Supabase project dashboard
2. Navigate to SQL Editor
3. Run the contents of `seed_ncb_test_keys.sql`

## Getting Real Test Credentials

The placeholder values (`TEST_PT_ID_12345`, etc.) need to be replaced with actual credentials from NCB/PowerTranz.

### Steps to Get Real Credentials:

1. **Contact NCB/PowerTranz**
   - Reach out to your NCB representative
   - Request sandbox/test API credentials for PowerTranz Direct

2. **Required Information**
   - PowerTranz ID (provided by NCB)
   - PowerTranz Password (provided by NCB)
   - Merchant ID (provided by NCB)

3. **Update the Configuration**
   - Edit `seed_ncb_test_keys.sql` with your real credentials
   - Run the seed script to update the database
   - Or update directly in Supabase dashboard → Table Editor → app_config

## Testing the Integration

Once credentials are configured:

1. **Start your app**
   ```bash
   flutter run
   ```

2. **Navigate to a payment screen**
   - Add items to cart
   - Proceed to checkout
   - Select "Pay with Card"

3. **Enter test card details**
   - Use a test card number (e.g., `4111 1111 1111 1111`)
   - Any future expiry date (e.g., `12/28`)
   - Any 3-digit CVV (e.g., `123`)
   - Any cardholder name

4. **Check the logs**
   - The edge function will log API calls
   - View logs in Supabase dashboard → Logs

## Troubleshooting

### "PowerTranz credentials missing" Error

If you see this error in the logs:

1. Check that credentials are set in `app_config`:
   ```sql
   SELECT key, value FROM app_config WHERE key LIKE 'ncb_%';
   ```

2. Ensure the keys are not empty strings

3. Run the seed script to update credentials

### Payment Always Returns "Mock Response"

This happens when credentials are missing or empty. The system falls back to a mock response for development.

**Solution**: Update the credentials with real values from NCB.

### API Connection Errors

If you see connection errors:

1. Verify `ncb_use_sandbox` is set correctly:
   - `1` for sandbox/testing
   - `0` for production

2. Check the API endpoints are correct:
   - Sandbox: `https://staging.ptranz.com/api/spi`
   - Production: `https://ptranz.com/api/spi`

## Security Notes

⚠️ **IMPORTANT**: 
- Never commit real API credentials to version control
- The test values in this repository are placeholders
- Always use environment variables or secure storage for production credentials
- Restrict database access to the `app_config` table

## Production Deployment

For production:

1. **Update credentials** with production values from NCB
2. **Set `ncb_use_sandbox` to `0`** to use production endpoint
3. **Use production API URLs** in the configuration
4. **Test thoroughly** in sandbox before going live

## Support

For issues with:
- **NCB/PowerTranz API**: Contact NCB technical support
- **Edge function errors**: Check Supabase logs
- **Database configuration**: Use Supabase dashboard

## Additional Resources

- [PowerTranz API Documentation](https://ptranz.com/api-docs)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [NCB Developer Portal](https://ncb.com/jm/developer) (if available)