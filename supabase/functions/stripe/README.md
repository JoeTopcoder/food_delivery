# `stripe` — consolidated Stripe Edge Function

One deployed function replacing **12** separate ones, to claw back slots against
the 100-function project ceiling. It is a thin path router (`index.ts`) over
route modules under `routes/`, each a **verbatim copy** of the function it
replaces (only the `serve()` wrapper became an exported `handle()` and import
depth was fixed). Payment, Connect, subscription, payout and webhook logic is
byte-for-byte what production runs today.

## Routes

| Method | Path | Replaces | Flutter caller |
|---|---|---|---|
| POST | `/stripe/payment` | `stripe-payment` | `payment_service.dart` |
| POST | `/stripe/connect` | `stripe-connect` (action-dispatched: status, create_account, update_kyc, add_bank, add_card) | `payout_service.dart`, `delayed_stripe_connect_service.dart` |
| POST | `/stripe/connect/account` | `create-connect-account` | `stripe_connect_service.dart` |
| POST | `/stripe/connect/onboarding` | `create-account-link` | `stripe_connect_service.dart` |
| POST | `/stripe/connect/status` | `refresh-connect-account` | `stripe_connect_service.dart` |
| POST | `/stripe/subscription` | `create-subscription` | `subscription_service.dart` |
| POST | `/stripe/pause-fee` | `charge-pause-fee` | `ride_service.dart` |
| POST | `/stripe/payout` | `stripe-pay-from-payout-request` | `admin_payouts_screen.dart` |
| POST | `/stripe/webhook` | `stripe-webhook` | Stripe (endpoint URL) |
| POST | `/stripe/webhook/connect` | `stripe-connect-webhook` | Stripe |
| POST | `/stripe/webhook/payout` | `stripe-payout-webhook` | Stripe |
| POST | `/stripe/webhook/subscription` | `stripe-subscription-webhook` | Stripe |

Request/response bodies are **unchanged**. Flutter migration is only the invoke
name string (e.g. `invoke('stripe-payment', …)` → `invoke('stripe/payment', …)`).

## Secrets (all already set in the project)
`STRIPE_SECRET_KEY` (+ legacy aliases `STRIPE_SK`/`STRIPE_API_KEY`),
`STRIPE_WEBHOOK_SECRET`, `STRIPE_CONNECT_WEBHOOK_SECRET`,
`STRIPE_PAYOUT_WEBHOOK_SECRET`, `STRIPE_SUBSCRIPTION_WEBHOOK_SECRET`,
`STRIPE_CONNECT_COUNTRY`, `APP_URL`, `SUPABASE_URL`,
`SUPABASE_SERVICE_ROLE_KEY`, `SUPABASE_ANON_KEY`. The four webhook secrets are
distinct — each webhook route verifies against its own, so consolidating does
not merge them.

## Status: BUILT, NOT DEPLOYED
Nothing here is live. `verify_jwt=false` is set in `supabase/config.toml`.
Not yet type-checked (no Deno in the build env) — that is a gate before deploy.

## Remaining migration steps (each needs explicit go-ahead)
1. Delete the orphan `create-payment-intent` (0 callers) to free a slot.
2. `supabase functions deploy stripe`, then curl-test every route.
3. Point the 4 Stripe Dashboard webhook URLs at `/stripe/webhook*` (secrets unchanged).
4. Switch the 7 Flutter service files to the new invoke names; verify each flow.
5. Only then delete the 12 replaced functions (100 → 88).
