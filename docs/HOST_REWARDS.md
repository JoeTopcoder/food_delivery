# HotBite Host Rewards — Deployment & Operations

Property hosts (Airbnb / guesthouse owners) earn a commission when a guest who
registered via the property's QR code has an order **delivered to that same
registered property**. Funded by HotBite, never from merchant proceeds.

The whole system is **inert until `app_config.host_rewards_enabled = 'true'`.**

## Architecture (reuses existing platform patterns)
- **Backend:** Supabase Postgres + RLS + `SECURITY DEFINER` RPCs + triggers; money
  in integer **cents**; all commission logic server-side & idempotent.
- **Commission engine:** `host_award_commission(order_id)` fires from
  `trg_host_commission` (orders `status → delivered`) and reverses via
  `host_reverse_commission` on cancel / processed-or-approved refund
  (`trg_host_commission_refund` on `refunds`).
- **Attribution:** `host_claim_referral(code)` (customer, authenticated-only,
  new-customer-only, 30-day configurable expiry).
- **Order linkage:** `orders.host_property_id` set by `place-order` /
  `grocery/order` **only** when the customer has an active referral to that
  property (server-authoritative).
- **Admin:** `/admin-host-rewards` (hosts, properties, QR PNG/card, commissions,
  payouts, settings).
- **Host portal:** role `host`, `/host-dashboard`, RLS self-read only.

## Migrations (apply in order, via the repo workaround)
`supabase db push` is broken repo-wide (history drift). Apply each file with:
```
supabase db query --linked -f supabase/migrations/<file>.sql
```
1. `20261025000000_host_rewards.sql` — tables, engine, triggers, admin RPCs, RLS.
2. `20261025010000_user_address_host_property.sql` — `user_addresses.host_property_id`.
3. `20261025020000_host_portal.sql` — `host` role, `hosts.user_id`, self-read RLS,
   host RPCs.

Edge functions to deploy: `supabase functions deploy place-order grocery`.

## Environment / configuration
No new secrets. Programme settings live in `host_rewards_config` (row id=1):
`default_commission_cents` (10000 = J$100), `commission_type` (fixed/percent),
`referral_days` (30), `hold_period_days` (7) — editable in Admin → Host Rewards →
Settings, which also flips the master flag.

## Going live (checklist)
1. Confirm all 3 migrations applied + both edge functions deployed.
2. Run the test suite (non-persisting):
   `supabase db query --linked -f supabase/tests/host_rewards_test.sql` → all pass.
3. In Admin → Host Rewards: register a host, add a property (gets a QR), optionally
   **Link login** (an existing account becomes a `host`).
4. Set the commission/days in Settings and toggle **Host Rewards enabled → ON**.
5. Verify end-to-end: scan QR (customer) → claim → save address → order → mark
   delivered → commission appears pending → approve payout.

## Rollback
- **Instant disable (no data loss):** Admin → Settings → toggle OFF, or
  `UPDATE app_config SET value='false' WHERE key='host_rewards_enabled';`
  The engine becomes a no-op immediately; existing records are preserved.
- **Full rollback (schema):** drop in reverse dependency order —
  `DROP TRIGGER trg_host_commission ON orders; DROP TRIGGER trg_host_commission_refund ON refunds;`
  drop the `host_*` functions, then `host_audit_logs, host_commission_ledger,
  host_payouts, host_commissions, host_referrals, host_properties,
  host_rewards_config, hosts`; `ALTER TABLE orders DROP COLUMN host_property_id;`
  `ALTER TABLE user_addresses DROP COLUMN host_property_id;`. (Keep the `host`
  value in the `users_role_check` constraint unless no host logins exist.)
  Prefer the instant-disable above; only drop schema if removing the feature
  entirely.

## Security
- All `host_*` tables RLS: admin full access; hosts self-read only; no anon.
- Engine/admin RPCs locked to `service_role` / `is_admin()`; claim is
  authenticated-only and pinned to `auth.uid()`.
- Commission uniqueness per order + idempotency-keyed ledger prevent double credit;
  reversal is idempotent. A spoofed `host_property_id` earns nothing (referral
  match + delivery required).

## Outstanding / manual setup
- **Deep link** `thehotbite.com/host/<CODE>` needs Android App Links / iOS
  Universal Links **domain verification** (assetlinks.json / apple-app-site-assoc
  + intent filters). In-app **QR scan + manual code entry work without it.**
- Host logins are created by an admin **Link login** to an existing account; there
  is no host self-signup yet.
- Grocery orders are attributed (food + grocery both covered); other verticals
  (rides/laundry/etc.) are not in scope.
