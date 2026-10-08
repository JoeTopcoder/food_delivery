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
| `models/` | Data models, grouped by domain: `user/ catalog/ ordering/ driver/ money/ rewards/ delivery/ comms/ platform/` (+ `stripe/`). `*.g.dart` are generated (snake_case JSON), live beside their source — avoid regen. |
| `providers/` | Riverpod providers, grouped by domain: `auth_user/ catalog/ ordering/ driver/ money/ rewards/ delivery/ comms/ admin/ platform/` (+ `stripe/`). |
| `services/` | Backend-call classes, grouped by area (see §4). |
| `screens/` | Screens, grouped **by role then feature** (see §3). |
| `widgets/` | Shared widgets, grouped: `common/ menu/ orders/ grocery/ driver/ comms/ home/`. |
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

## 3. `screens/` — grouped by role, then by feature

The four big role folders are now split into **feature subfolders**:

| Role folder | Feature subfolders |
|---|---|
| `screens/customer/` | `home/` `ordering/` `grocery/` `wallet_payments/` `rewards/` `account/` |
| `screens/admin/` | `core/` `operations/` `people/` `catalog/` `finance/` `marketing/` `ai/` `config/` (+ `ai_staff/`) |
| `screens/driver/` | `deliveries/` `earnings/` `onboarding/` `performance/` `home/` |
| `screens/restaurant/` | `home/` `orders/` `menu/` `marketing/` `staff/` |

Smaller role folders stay flat: `legal/` (compliance screens), `shared/`
(cross-role), `company/` (sponsored ordering), `auth/`, `stripe/`, `staff/`,
`permissions/`.

Quick guide to the subfolders:
- **customer**: `home` = browse/discovery/reviews · `ordering` = cart/checkout/order
  tracking/group orders · `grocery` · `wallet_payments` · `rewards` =
  referrals/loyalty/membership · `account` = profile/address/notifications.
- **admin**: `core` = shell/overview/MFA · `operations` = orders/dispatch/support ·
  `people` = users/drivers · `catalog` = restaurants/menu/grocery · `finance` =
  payouts/pricing/wallet · `marketing` = promos/banners/campaigns · `ai` =
  AI/intelligence/analytics · `config` = regions/services/settings.
- **driver**: `deliveries` · `earnings` · `onboarding` = KYC/verification ·
  `performance` = priority/leaderboard · `home` = dashboard/profile.
- **restaurant**: `home` = dashboard/settings · `orders` = order mgmt/picking ·
  `menu` · `marketing` · `staff`.

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
| **Flip or add a feature flag** | `providers/platform/feature_providers.dart` (backed by the `app_config` table; read at app start). |
| **Theme / colours** | `utils/app_theme.dart` (+ `ThemeService`). |
| **Timestamps (Jamaica time)** | `utils/est_datetime.dart` — use `toJamaicaOf(...)` / `jmFormat(...)`. |
| **Current user / auth state** | `providers/auth_user/auth_provider.dart` — `currentUserProvider`, `currentUserIdProvider`. |
| **Cart** | `providers/auth_user/user_provider.dart` — `cartProvider` (100% client-side, no cart table). |
| **Wallet / money movement** | `providers/money/` (wallet_provider…) + audited RPCs (`admin_wallet_adjust`, `wallet_transfer`). |
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

Done (incremental, each analyze + build verified):
- ✅ `screens/` (customer, admin, driver, restaurant) → feature subfolders (§3).
- ✅ `providers/`, `models/`, `widgets/` → domain subfolders (§2).

Still open — safe as a **bounded, build-verified** pass:

1. Move the 21 loose `services/*.dart` into their domain subfolders (§4 table).

Each involves rewriting imports, so do one at a time and run `flutter analyze`
(baseline = a few pre-existing issues) before committing.
