# 7Dash — Codebase Guide

Multi-vertical delivery platform (Flutter + Riverpod + Supabase). Legal entity
SevenDash Technologies Limited. Verticals: **food delivery, rides/taxi, laundry,
car services, package delivery, grocery, hotels**. Four roles: customer, driver,
restaurant/provider, admin — plus a parallel web build.

## Stack

| | |
|---|---|
| Flutter | Dart SDK `^3.9.0` |
| State | `flutter_riverpod` ^2.6.1 (`StateNotifierProvider`, `StreamProvider`, `FutureProvider`) |
| Backend | `supabase_flutter` ^2.1.0 — Postgres + RLS + Realtime + Edge Functions (Deno) |
| Payments | `flutter_stripe` ^11.5.0 + Stripe Connect (driver/restaurant payouts) |
| Scale | 482 Dart files · ~170 tables · 287 migrations · 104 edge functions · 17 test files |

## Layout

```
lib/
  main.dart        193 routes in one onGenerateRoute switch — add routes HERE
  models/          36 files; *.g.dart are json_serializable (snake_case keys)
  providers/       33 Riverpod providers — auth, cart, wallet, driver, feature flags
  services/        49 files, grouped: ai/ driver/ food/ payment/ …
  screens/         155 files by role: admin/ auth/ customer/ driver/ restaurant/ shared/
  modules/         98 files — self-contained verticals: rides/ laundry/ car_services/ packages/
  features/        newer feature-first slices (auth, customer, driver, restaurant)
  widgets/ utils/ core/ config/ l10n/
  web/             62 files — separate web UI per role
supabase/
  migrations/      287 .sql, roughly timestamp-ordered
  functions/       104 Deno edge functions
```

**Where things live:** routes → `main.dart`. Feature flags → `providers/feature_providers.dart`
(backed by the `app_config` table). Theme → `utils/app_theme.dart`. Money/currency →
`AppConstants.currencySymbol` / `AppConstants.currencyCode` (never hardcode a currency).

## Commands

```bash
flutter analyze                      # baseline is 6 PRE-EXISTING issues — that's clean
flutter test                         # plain flutter_test, no extra harness
flutter build apk --debug            # ~3-4 min; background it
flutter pub get
```

Migrations — **`supabase db push` is broken repo-wide** (pre-existing migration-history
drift). The established workaround, used for every migration:

```bash
supabase db query --linked -f supabase/migrations/<file>.sql
```

Device (Samsung A16 / SM_A165M is the test phone):

```bash
MSYS_NO_PATHCONV=1 adb install -r --no-streaming build/app/outputs/flutter-apk/app-debug.apk
MSYS_NO_PATHCONV=1 adb shell am force-stop sevendash.app
MSYS_NO_PATHCONV=1 adb shell monkey -p sevendash.app -c android.intent.category.LAUNCHER 1
MSYS_NO_PATHCONV=1 adb exec-out screencap -p > shot.png   # then actually LOOK at it
```

`MSYS_NO_PATHCONV=1` is required for any adb path under `/data/` or `/sdcard/`, and
`--no-streaming` for this device's flaky USB install. `adb` may drop to `unauthorized`
— the user must re-accept the debugging prompt.

## Hard-won gotchas

**Migrations drift from live.** A migration file existing does NOT mean it was applied,
and *parts* of one migration can be live while other parts were later overwritten. A real
bug: `wallet_transfer()` shipped alongside a CHECK-constraint change; a later migration
rebuilt that constraint from an older list, so the function inserted a type its own table
rejected — every transfer failed for months. **Always verify against the live DB** before
concluding code is correct:

```sql
SELECT p.proname, pg_get_function_identity_arguments(p.oid)
FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='public';
SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname='…';
```

End every migration with `NOTIFY pgrst, 'reload schema';`.

**`SECURITY DEFINER` + a caller-supplied user id = an auth hole.** Several RPCs take
`p_user_id`/`p_sender_id` and are granted to `authenticated`. If nothing ties that
parameter to `auth.uid()`, any logged-in user can act as anyone. Pattern used in
`wallet_transfer`: pin to `auth.uid()` when it's non-NULL (JWT callers), fall back to the
parameter only when NULL (service-role/direct SQL).

**Ledger sign convention:** `wallet_transactions` stores **debits negative**
(`payment` = −11.43) and **credits positive**. The wallet history renders direction purely
from `tx.amount > 0`. Any new money-moving code must respect this. `wallets.balance` is
authoritative — nothing derives a balance by summing the ledger, and some users' ledger
sums legitimately don't reconcile with their balance (historical direct adjustments).

**Cart is 100% client-side.** `CartNotifier extends StateNotifier<List<CartItem>>`
(`providers/user_provider.dart`, `cartProvider` ~line 1102), persisted to
`SharedPreferences`. There is **no cart table**. `CartItem` has no per-line id — lines are
identified by `menuItem.id` + sides/options equality, so `removeItem`/`updateQuantity`
affect *every* line sharing a menu item id. Known limitation, not a bug to "fix" casually.
`addItem` already merges same-config items and splits differing-modifier ones.

**Provider staleness.** `walletNotifierProvider`-style `StateNotifier`s load **once** in
their constructor. Snapshotting one into a widget gives stale data — a real bug had the
Send Money sheet showing `$0.00` and rejecting every transfer, because the row was created
after app start. Prefer the `*StreamProvider` (Realtime) that the surrounding UI already
watches, and re-read at submit time rather than trusting a value captured at open.

**Bottom sheets need both insets.** `viewInsets.bottom` clears the keyboard;
`padding.bottom` clears the system nav bar. Missing the latter renders buttons *underneath*
the nav bar where taps go to the system — a button that looks fine and is completely dead.
Tall sheets also need a `SingleChildScrollView` + capped `maxHeight`.

**`.g.dart` files use snake_case JSON keys** (`owner_id`, `image_url`, `cuisine_type`).
Regenerating with build_runner touches shared models — avoid unless necessary; prefer a
targeted query over remodeling.

**Realtime requires publication membership.** If a table isn't in `supabase_realtime`,
streams silently never fire. Check `pg_publication_tables`. Realtime also respects RLS.

## Model/provider facts

- `currentUserProvider` and `currentUserIdProvider` live in `providers/auth_provider.dart`
- Driver screens use `driverProfileProvider(userId)`, not `currentUser?.id`
- `Driver` model: `completedDeliveries`, `rating` (not `totalDeliveries`/`averageRating`)
- `MenuItem`: use the `discountedPrice` getter, not `price`, for cart display
- Feature flags follow the `multiRestaurantEnabledProvider` pattern in
  `feature_providers.dart` — a `FutureProvider<bool>` watching `configVersionProvider`,
  which an `app_config` Realtime subscription bumps. **Flags are read at app start**, so a
  flag flipped in the DB needs a force-stop + relaunch to take effect reliably.

## Verification standard

This repo has **no edge-function test harness**. The established practice is real
verification, not fabricated tests:

- SQL/RPC changes → run them against the live DB inside `BEGIN; … ROLLBACK;` so nothing
  persists, and test the negative cases (unauthorized, insufficient, not-found, bad input)
- Edge functions → `curl` the deployed function with a real session JWT
- UI changes → build, install, screenshot, **look at the screenshot**
- Always re-run `flutter analyze` and confirm you're back at the 6-issue baseline

This is a **production database with real users, real money, and live Stripe**. Prefer
transactions you roll back. For anything that moves money, use the existing audited RPCs
(`admin_wallet_adjust` writes an `admin_credit` ledger row) rather than a raw `UPDATE`,
which would desync balance from ledger.
