# Stripe Connect Express Payout System — Deployment Guide

## Overview

This guide covers deploying the complete Stripe Connect payout system for 7Dash.
The system uses Stripe Connect Express accounts, Supabase Edge Functions, and a
Flutter frontend.

---

## 1. Stripe Dashboard Setup

### 1.1 Create a Stripe Account (if needed)
- Go to https://dashboard.stripe.com
- Complete business verification for your platform account

### 1.2 Enable Stripe Connect
1. Dashboard → **Connect** → **Settings**
2. Under **Connect onboarding options**, enable **Express** accounts
3. Set your platform name to **7Dash** and upload a logo
4. Set support URL, privacy policy URL, and terms of service URL
5. Under **Payout schedule**, leave as the default (connected accounts control their own)

### 1.3 Branding for Express Onboarding
- Dashboard → **Connect** → **Settings** → **Branding**
- Upload icon and brand color (#7C3AED) so Express onboarding shows 7Dash branding

### 1.4 Configure Webhook Endpoint
*(See Section 3 below — do this after deploying the Edge Function)*

### 1.5 Get API Keys
- Dashboard → **Developers** → **API keys**
- Copy **Secret key** (starts with `sk_live_` in production, `sk_test_` in test)
- **Never** commit these to source control

---

## 2. Supabase Setup

### 2.1 Run the Migration
```bash
supabase db push
# or apply the specific migration:
supabase migration up
```

Verify tables were created:
```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'stripe_connected_accounts',
    'earnings_ledger',
    'payout_requests',
    'payout_request_ledger_entries',
    'stripe_webhook_events',
    'app_payout_settings'
  );
```

### 2.2 Set Supabase Secrets

Run these in your project root (requires Supabase CLI logged in):

```bash
# Stripe secret key (test or live)
supabase secrets set STRIPE_SECRET_KEY=sk_test_YOUR_KEY_HERE

# Stripe webhook signing secret (get this from Step 3)
supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_YOUR_SECRET_HERE

# App URL for Stripe redirect URLs
supabase secrets set APP_URL=https://7dash.app

# Secret for the release-available-earnings cron endpoint
supabase secrets set RELEASE_EARNINGS_SECRET=$(openssl rand -hex 32)
```

Verify secrets are set:
```bash
supabase secrets list
```

### 2.3 Deploy Edge Functions

```bash
# Deploy all new functions at once
supabase functions deploy create-connect-account
supabase functions deploy create-account-link
supabase functions deploy refresh-connect-account
supabase functions deploy get-earnings-summary
supabase functions deploy request-payout
supabase functions deploy approve-payout-request
supabase functions deploy reject-payout-request
supabase functions deploy retry-payout-request
supabase functions deploy release-available-earnings
supabase functions deploy create-earning-entry
supabase functions deploy stripe-connect-webhook
```

Or deploy all at once:
```bash
supabase functions deploy
```

### 2.4 Verify Function URLs

Each function will be available at:
```
https://yharweliruemjexmuuxn.supabase.co/functions/v1/<function-name>
```

Test with curl:
```bash
curl -X OPTIONS \
  https://yharweliruemjexmuuxn.supabase.co/functions/v1/get-earnings-summary
# Should return 200 with CORS headers
```

### 2.5 Configure release-available-earnings as a Cron Job

In the Supabase dashboard → **Database** → **Extensions**, enable `pg_cron`.
Then run:

```sql
-- Run every hour to release earnings whose hold period has elapsed
SELECT cron.schedule(
  'release-available-earnings',
  '0 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://yharweliruemjexmuuxn.supabase.co/functions/v1/release-available-earnings',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || current_setting('app.release_earnings_secret'),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  ) AS request_id;
  $$
);
```

Then set the app config:
```sql
ALTER DATABASE postgres SET app.release_earnings_secret = 'YOUR_RELEASE_EARNINGS_SECRET';
```

---

## 3. Stripe Webhook Registration

### 3.1 Register the Webhook Endpoint

1. Stripe Dashboard → **Developers** → **Webhooks** → **Add endpoint**
2. Endpoint URL:
   ```
   https://yharweliruemjexmuuxn.supabase.co/functions/v1/stripe-connect-webhook
   ```
3. Select events to listen for:
   - `account.updated`
   - `payout.paid`
   - `payout.failed`
   - `payout.canceled`
   - `transfer.created`
   - `transfer.reversed`
4. Click **Add endpoint**
5. Copy the **Signing secret** (starts with `whsec_`)
6. Run:
   ```bash
   supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_YOUR_SECRET
   supabase functions deploy stripe-connect-webhook
   ```

### 3.2 Test Webhook Delivery
- Stripe Dashboard → Webhooks → your endpoint → **Send test event**
- Choose `account.updated` and verify it appears in `stripe_webhook_events` table

---

## 4. Flutter Environment

### 4.1 Add url_launcher dependency

`pubspec.yaml` should already include `url_launcher`. If not:
```yaml
dependencies:
  url_launcher: ^6.3.0
```

```bash
flutter pub get
```

### 4.2 Android — url_launcher setup

`android/app/src/main/AndroidManifest.xml` — add inside `<manifest>`:
```xml
<queries>
  <intent>
    <action android:name="android.intent.action.VIEW" />
    <data android:scheme="https" />
  </intent>
  <intent>
    <action android:name="android.intent.action.VIEW" />
    <data android:scheme="http" />
  </intent>
</queries>
```

### 4.3 iOS — url_launcher setup

`ios/Runner/Info.plist` — add:
```xml
<key>LSApplicationQueriesSchemes</key>
<array>
  <string>https</string>
  <string>http</string>
</array>
```

### 4.4 Add New Screens to Routes

In `lib/main.dart`, inside the `onGenerateRoute` switch, add:

```dart
case '/earnings':
  final args = settings.arguments as Map<String, dynamic>?;
  return MaterialPageRoute(
    builder: (_) => EarningsDashboardScreen(
      role: args?['role'] as String? ?? 'driver',
    ),
  );

case '/payout-setup':
  final args = settings.arguments as Map<String, dynamic>?;
  return MaterialPageRoute(
    builder: (_) => PayoutSetupScreen(
      role: args?['role'] as String? ?? 'driver',
    ),
  );

case '/admin/payout-requests':
  return MaterialPageRoute(
    builder: (_) => const AdminPayoutRequestsScreen(),
  );
```

Add the imports at the top of `main.dart`:
```dart
import 'screens/stripe/earnings_dashboard_screen.dart';
import 'screens/stripe/payout_setup_screen.dart';
import 'screens/stripe/admin_payout_requests_screen.dart';
```

### 4.5 Link from Existing Screens

**Driver Dashboard** — add earnings tile:
```dart
ListTile(
  leading: const Icon(Icons.account_balance_wallet_outlined),
  title: const Text('My Earnings'),
  onTap: () => Navigator.pushNamed(
    context, '/earnings', arguments: {'role': 'driver'}),
),
```

**Admin Dashboard** — add payout management tile:
```dart
ListTile(
  leading: const Icon(Icons.payments_outlined),
  title: const Text('Payout Requests'),
  onTap: () => Navigator.pushNamed(context, '/admin/payout-requests'),
),
```

**Restaurant Dashboard** — add earnings tile:
```dart
ListTile(
  leading: const Icon(Icons.account_balance_wallet_outlined),
  title: const Text('Earnings & Payouts'),
  onTap: () => Navigator.pushNamed(
    context, '/earnings', arguments: {'role': 'restaurant'}),
),
```

---

## 5. Local Testing with Stripe CLI

### 5.1 Install Stripe CLI
```bash
# macOS
brew install stripe/stripe-cli/stripe

# Windows (scoop)
scoop install stripe

# Or download from: https://github.com/stripe/stripe-cli/releases
```

### 5.2 Login
```bash
stripe login
```

### 5.3 Forward webhooks to local Supabase
```bash
# Start Supabase locally first
supabase start

# Forward Stripe events to local function
stripe listen --forward-to localhost:54321/functions/v1/stripe-connect-webhook
```

The CLI will output a webhook signing secret like `whsec_test_...`. Set it:
```bash
# For local testing, add to supabase/functions/.env
echo "STRIPE_WEBHOOK_SECRET=whsec_test_..." >> supabase/functions/.env
echo "STRIPE_SECRET_KEY=sk_test_..." >> supabase/functions/.env
echo "APP_URL=http://localhost:3000" >> supabase/functions/.env
```

### 5.4 Trigger Test Events
```bash
# Simulate a payout paid event
stripe trigger payout.paid

# Simulate account.updated (onboarding complete)
stripe trigger account.updated

# Simulate a transfer reversal
stripe trigger transfer.reversed

# Watch events in real time
stripe events tail
```

### 5.5 Create a Test Connected Account (Express)
In test mode Express onboarding, use these test credentials:
- Any routing number: `110000000`
- Account number: `000123456789`
- Use test personal info from: https://stripe.com/docs/connect/testing

---

## 6. Crediting Earnings (Integration)

When an order is completed, call `create-earning-entry` from your
`complete-delivery` or `place-order` Edge Function:

```typescript
// Inside complete-delivery/index.ts
import { serviceClient } from '../stripe-shared/supabase.ts'

// Credit driver
await serviceClient.functions.invoke('create-earning-entry', {
  body: {
    user_id: driverUserId,
    role: 'driver',
    order_id: orderId,
    driver_id: driverProfileId,
    type: 'order_earning',
    direction: 'credit',
    amount_cents: driverEarningCents,   // e.g. order subtotal × 0.80
    currency: 'usd',
    description: `Order #${orderNumber} delivery fee`,
    metadata: { order_number: orderNumber },
  },
  headers: {
    Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
  },
})

// Credit restaurant
await serviceClient.functions.invoke('create-earning-entry', {
  body: {
    user_id: restaurantUserId,
    role: 'restaurant',
    order_id: orderId,
    restaurant_id: restaurantProfileId,
    type: 'order_earning',
    direction: 'credit',
    amount_cents: restaurantEarningCents,  // e.g. order subtotal × 0.70
    currency: 'usd',
    description: `Order #${orderNumber} food sales`,
  },
  headers: {
    Authorization: `Bearer ${Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')}`,
  },
})
```

---

## 7. Production Checklist

### Stripe
- [ ] Switch from `sk_test_` to `sk_live_` secret key
- [ ] Switch from `whsec_test_` to live webhook signing secret
- [ ] Verify webhook endpoint is registered in live mode
- [ ] Test one full payout flow end-to-end in live mode with a real bank account
- [ ] Enable Stripe Radar fraud rules for your platform
- [ ] Set `require_admin_approval = true` in `app_payout_settings` initially
- [ ] Review connected account payout schedules (daily/weekly/manual)

### Supabase
- [ ] All 6 new tables exist with RLS enabled
- [ ] All 5 RPC functions deployed
- [ ] All 11 Edge Functions deployed and returning 200 on OPTIONS
- [ ] `STRIPE_SECRET_KEY` secret set to live key
- [ ] `STRIPE_WEBHOOK_SECRET` secret set to live webhook secret
- [ ] `RELEASE_EARNINGS_SECRET` set and cron job scheduled
- [ ] Verify `app_payout_settings` row exists with correct `min_payout_cents`

### Flutter
- [ ] Routes added to `main.dart`
- [ ] Entry points added to Driver/Restaurant/Admin dashboards
- [ ] `url_launcher` AndroidManifest / Info.plist configured
- [ ] `flutter analyze` returns 0 errors

### Operations
- [ ] Create reviewer Stripe test account before App Store review
- [ ] Add Stripe dashboard access for ops team
- [ ] Set up Stripe email notifications for failed payouts
- [ ] Document payout approval process for admin team
- [ ] Set hold days (`driver_hold_days`, `restaurant_hold_days`) to match
      your dispute window (recommended: 7 days for launch)
