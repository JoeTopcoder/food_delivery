# Cooking Gas (LPG) Delivery Module

A hazardous-goods delivery vertical built **alongside** food/grocery, sharing
customers, addresses, wallet and notifications but with its own schema, state
machine and **supplier-managed** fulfilment. Cooking gas never enters the food
rider dispatch pool.

Status: **backend + Flutter UI complete, flag OFF.** Not for live LPG ordering
until the regulatory sign-off below is done.

## Feature flags (both default OFF)
| Key (`app_config`) | Purpose |
|---|---|
| `gas_enabled` (+ `gas_settings.enabled`) | Backend kill switch — `place_gas_order` refuses when false |
| `service_gas_enabled` | Customer home "Cooking Gas" launcher tile visibility |

Flip in the DB, then force-stop + relaunch the app (flags load at startup).

## Architecture
- **13 `gas_*` tables** (migration `20261119100000_gas_foundation.sql`), money in
  **JMD cents**, 19 RLS policies, helper `can_manage_gas_supplier()`.
- **Lifecycle RPCs** (`20261119110000_gas_rpcs.sql`): `place_gas_order`
  (server-authoritative totals + atomic stock reservation + zone enforcement),
  `gas_order_transition` (validated 15-state machine, role-gated),
  `gas_exchange_decide`, `gas_assign_operator`.
- **Payment** (`20261119120000_gas_payment_rpcs.sql`): `gas_pay_wallet`
  (audited ledger debit), `gas_confirm_payment` (service-role webhook callback);
  edge function `gas-pay-order` (Stripe card at `usd_jmd_rate`).
- **Financials** (`20261119130000_gas_financials.sql`): `get_gas_financials` —
  deposits + unpaid payouts tracked as **liabilities**, platform revenue =
  service fees + commission + delivery.
- **Flutter**: `lib/modules/gas/` (models, service, providers, customer/supplier/
  admin screens). Routes `/gas`, `/gas-supplier-dashboard`, `/gas-admin` in
  `main.dart`. Tile in `service_launcher_grid.dart`.

## Order state machine
`pending_supplier → supplier_accepted → awaiting_payment → payment_confirmed →
preparing → assigned → out_for_delivery → delivered → [exchange_completed] →
completed`. Branches: `rejected`, `cancelled` (pre-delivery, restores stock),
`failed_delivery → assigned|refund_pending → refunded`. Payment status is
tracked separately from fulfilment status.

## Money invariants
- Cylinder **deposits are a refundable liability**, never platform revenue.
- Supplier & delivery-operator **payouts are liabilities until paid** — not profit.
- `wallet_transactions.order_id` FKs to `orders`, so gas wallet payments leave it
  NULL and name the gas order in `description` (dollars, `type='payment'`, negative).
- Gas money is JMD **cents**; wallet is **dollars** — convert `cents/100`.

## Deployment checklist
1. [ ] Apply migrations (already applied to live DB via `supabase db query --linked`):
   `20261119100000`, `110000`, `120000`, `130000`.
2. [ ] `supabase functions deploy gas-pay-order` (needs `STRIPE_SECRET_KEY`,
   `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`). Set `verify_jwt` per the
   project's convention (the fn authenticates the JWT itself).
3. [ ] Onboard a real approved supplier: insert `gas_suppliers` row (owner =
   existing `restaurant`-role user), upload licence/insurance to
   `gas_supplier_verifications`, set `verification_status='approved'`,
   `delivery_operational=true`, `accepting_orders=true`.
4. [ ] Add `gas_products`, `gas_delivery_zones`, and eligible
   `gas_delivery_operators` for that supplier.
5. [ ] Verify Stripe path end-to-end with a real session JWT on a test order.
6. [ ] Flip `gas_enabled` and `service_gas_enabled` to `true`; force-stop +
   relaunch; confirm the tile and an end-to-end order.
7. [ ] Add supplier-dashboard + admin entry points to the respective shells if
   not already surfaced (routes exist: `/gas-supplier-dashboard`, `/gas-admin`).

## ⚠️ Regulatory / operational assumptions — REQUIRE HUMAN VERIFICATION
The code does **not** assert legal compliance. Before enabling live LPG ordering,
HotBite must verify and configure:
- **Jamaican LPG transport/handling law** — who may legally transport filled
  cylinders, vehicle requirements, quantity limits. The
  `gas_delivery_operators` eligibility fields (`transport_auth_ref`,
  `insurance_ref`, `training_ref`, `eligible`) are **configurable placeholders**.
- **Supplier licensing & insurance** — validated out-of-band; store evidence in
  `gas_supplier_verifications`. Admin approval is mandatory before orders.
- **Emergency procedures** — the in-app safety note tells customers to move away
  from a suspected leak, avoid ignition, and call the supplier/emergency
  services. HotBite personnel must **not** install, connect, repair, refill or
  inspect LPG equipment; those services stay disabled.
- **Do not pre-list** brands (IGL, GasPro, FESGAS) as partners until an
  authorised supplier is actually onboarded and approved.

## Known follow-ups
- Supplier/admin dashboard entry points in the existing shells (routes ready).
- Stripe/NCB webhook wiring for card renewals/refunds (confirm RPC is ready).
- Deposit-refund flow on cylinder return (liability already modelled).
- Automated widget/integration tests (backend verified via SQL rollback suites).
