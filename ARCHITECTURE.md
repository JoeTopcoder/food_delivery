# HotBite — Codebase Navigation Map

A practical map of `lib/` so you can find things fast. HotBite is a multi-vertical
delivery platform (**Flutter + Riverpod + Supabase**). Four roles — customer,
driver, restaurant/provider, admin — plus a parallel web build.

> New here? Read this top-to-bottom once, then use the **"I want to… where do I go?"**
> table as your day-to-day index.

---

## 1. The 30-second mental model

```
UI (screens / widgets)
        │  watches
        ▼
State (providers — Riverpod)
        │  calls
        ▼
Services (one class per backend area)
        │  talks to
        ▼
Supabase  (Postgres + RLS + Realtime + Edge Functions)
```

- **Screens** render and read state; they don't call Supabase directly.
- **Providers** hold state and expose it (`StateNotifier` / `Stream` / `Future`).
- **Services** are the only layer that talks to Supabase / Stripe / etc.
- **Models** are the data shapes passed between layers.

---

## 2. Top-level `lib/` layout

| Folder | What lives here |
|---|---|
| `main.dart` | App entry **and all 232 routes** (one `onGenerateRoute` switch). Add routes HERE. |
| `firebase_options.dart` | Generated Firebase config. Don't hand-edit. |
| `config/` | `app_constants.dart` (currency, fees, support info), `supabase_config.dart` (client). |
| `core/` | Cross-cutting primitives. Today: `utils/responsive.dart`. |
| `models/` | 43 data models. `*.g.dart` are generated (snake_case JSON) — avoid regen. |
| `providers/` | 45 Riverpod providers — auth, cart, wallet, driver, feature flags, weather… |
| `services/` | Backend-call classes, grouped by area (see §4). |
| `screens/` | 201 screens, grouped **by role** (see §3). |
| `widgets/` | 37 shared, reusable widgets (cards, banners, the weather card, logo…). |
| `features/` | Newer **feature-first** slices (ui+state+service+model together): auth, voice_ordering, concierge, coverage, customer, driver, restaurant, car_services, recipient. |
| `modules/` | 98 files — self-contained verticals: `rides/`, `laundry/`, `car_services/`, `packages/`. |
| `web/` | 62 files — the separate web UI per role. |
| `utils/` | 13 helpers — theme, time (Jamaica), logging, formatting, errors. |
| `l10n/` | Localization. |

**Two patterns coexist on purpose:** older code is **layer-first**
(`screens/` + `providers/` + `services/`), newer code is **feature-first**
(`features/<name>/…`). When adding a brand-new, self-contained feature, prefer a
`features/` slice. When extending existing areas, follow the layer-first folders.

---

## 3. `screens/` — grouped by role

| Folder | Count | For |
|---|---|---|
| `screens/admin/` | 79 | Admin console: orders, users, wallets, config, AI staff, reports, dashboards. |
| `screens/customer/` | 44 | The customer app: home, cart, checkout, grocery, wallet, company, earn… |
| `screens/driver/` | 23 | Driver app: dashboard, delivery flow, earnings, float. |
| `screens/restaurant/` | 15 | Restaurant portal: orders, menu, grocery mgmt, staff, cashier shifts. |
| `screens/legal/` | 13 | 17 compliance/legal screens (privacy, terms, deletion…). |
| `screens/shared/` | 8 | Cross-role screens (call screen, notifications…). |
| `screens/company/` | 5 | Company-sponsored ordering (My Company, dashboard, members…). |
| `screens/auth/` | 4 | Login / signup / reset (classic). Newer auth is in `features/auth/`. |
| `screens/stripe/` | 4 | Stripe Connect / payout onboarding. |
| `screens/staff/` | 1 | Accept-staff-invite. |
| `screens/permissions/` | 1 | Runtime permission prompts. |

> `screens/admin/` (79) and `screens/customer/` (44) are the two big flat folders.
> If they grow further, the next cleanup is to split them into feature subfolders
> (e.g. `customer/{home,cart,grocery,wallet,company}`) — see §7.

---

## 4. `services/` — grouped by area

Subfolders already exist for most areas:

| Folder | For |
|---|---|
| `services/ai/` | AI concierge, voice assistant, support agent. |
| `services/food/` | Restaurants, menus, categories, search. |
| `services/payment/` + `services/stripe/` | Payments, Stripe Connect, payouts. |
| `services/driver/` | Driver profile, intelligence, float. |
| `services/social/` | Sharing / social. |
| `services/company/`, `services/referral/`, `services/reorder/`, `services/restaurant/`, `services/admin/`, `services/call/` | One-area clients. |

**Loose files still directly in `services/`** (21) — where each belongs by domain:

| File | Domain |
|---|---|
| `auth_service.dart`, `mfa_service.dart` | auth |
| `user_service.dart`, `address_service.dart` | user/profile |
| `notification_service.dart`, `realtime_service.dart` | messaging/realtime |
| `grocery_service.dart`, `order_picking_service.dart` | grocery |
| `earning_service.dart`, `loyalty_service.dart`, `promo_service.dart` | rewards |
| `group_order_service.dart` | ordering |
| `location_service.dart`, `weather_service.dart` | location |
| `student_id_ocr_service.dart`, `student_verification_service.dart` | student verification |
| `compliance_service.dart`, `app_config_service.dart`, `admin_service.dart` | platform/admin |
| `api_client.dart`, `cache_service.dart` | infrastructure |

> These are documented here rather than moved, because a few (`notification_service`
> especially) are imported in many places and moving them is an import-rewrite job.
> Group them only as a deliberate, build-verified pass.

---

## 5. "I want to… where do I go?"

| Task | Go to |
|---|---|
| **Add / change a route** | `main.dart` — the `onGenerateRoute` switch. |
| **Change money / currency / fees** | `config/app_constants.dart` (`currencySymbol`, `currencyCode`, fee calc). Never hardcode a currency. |
| **Flip or add a feature flag** | `providers/feature_providers.dart` (backed by the `app_config` table; read at app start). |
| **Theme / colours** | `utils/app_theme.dart` (+ `ThemeService`). |
| **Timestamps (Jamaica time)** | `utils/est_datetime.dart` — use `toJamaicaOf(...)` / `jmFormat(...)`. |
| **Current user / auth state** | `providers/auth_provider.dart` — `currentUserProvider`, `currentUserIdProvider`. |
| **Cart** | `providers/user_provider.dart` — `cartProvider` (100% client-side, no cart table). |
| **Wallet / money movement** | `providers/` wallet providers + audited RPCs (`admin_wallet_adjust`, `wallet_transfer`). |
| **A customer screen** | `screens/customer/` (or `features/customer/`). |
| **A driver screen** | `screens/driver/` — driver id via `driverProfileProvider(userId)`. |
| **An admin screen** | `screens/admin/`. |
| **A Supabase call** | the matching `services/<area>/` class — add there, not in the UI. |
| **A reusable widget** | `widgets/`. |
| **A whole vertical (rides/laundry/packages)** | `modules/<vertical>/`. |
| **The web UI** | `web/<role>/`. |
| **Edge functions / SQL** | `supabase/functions/` and `supabase/migrations/` (see root `CLAUDE.md`). |

---

## 6. Conventions worth knowing

- **Models**: `*.g.dart` use snake_case JSON keys; regenerating touches shared
  models, so prefer a targeted query over remodeling.
- **Providers**: many `StateNotifier`s load once in their constructor — prefer the
  matching `*StreamProvider` for live data; re-read at submit time.
- **Driver model**: `completedDeliveries`, `rating` (not `totalDeliveries` / `averageRating`).
- **MenuItem**: use the `discountedPrice` getter (not `price`) for cart display.
- **Bottom sheets**: clear both `viewInsets.bottom` (keyboard) and `padding.bottom`
  (nav bar), scroll + cap height.
- Deeper backend gotchas (migration drift, RLS, ledger sign convention, realtime
  publication membership) live in the root **`CLAUDE.md`**.

---

## 7. Known tidy-ups (optional, not yet done)

These are safe to do later as **bounded, build-verified** passes — none are required:

1. Split `screens/admin/` (79) and `screens/customer/` (44) into feature subfolders.
2. Move the 21 loose `services/*.dart` into their domain subfolders (§4 table).
3. Group `providers/` (45) and `widgets/` (37) by area.

Each involves rewriting imports, so do one at a time and run `flutter analyze`
(baseline = a few pre-existing issues) before committing.
