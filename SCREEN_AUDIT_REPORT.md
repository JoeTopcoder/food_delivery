# Screen Audit Report — Food Driver App

> Full audit of all screen files. Covers providers, service methods, routes, broken buttons, hardcoded data, state management bugs, null safety issues, and missing functionality.

---

## Table of Contents

1. [Critical Bugs](#1-critical-bugs)
2. [Auth Screens](#2-auth-screens)
3. [Customer Screens](#3-customer-screens)
4. [Driver Screens](#4-driver-screens)
5. [Restaurant Screens](#5-restaurant-screens)
6. [Admin Screens](#6-admin-screens)
7. [Shared Screens](#7-shared-screens)
8. [Legacy Screens (lib/screens/user/)](#8-legacy-screens)
9. [Summary Tables](#9-summary-tables)

---

## 1. Critical Bugs

These are the highest-impact issues that will cause crashes, navigation failures, or data loss:

| # | Severity | File | Bug |
|---|----------|------|-----|
| 1 | **CRITICAL** | `main.dart` | **`/role-selection` route is NOT defined** but is used by `profile_screen.dart`, `driver_profile_screen.dart`, and `user_profile_screen.dart` for logout. Navigation will fall through to the default route (MainNavigationScreen) instead of showing role selection. |
| 2 | **CRITICAL** | `checkout_screen.dart` (customer) | **Currency mismatch**: Driver tip presets and custom tip use `$` (dollar sign) while the rest of the app uses `৳` (Taka). The order summary shows tip in `$` but total in `৳`, meaning the displayed total is visually incoherent. |
| 3 | **CRITICAL** | `available_orders_screen.dart` | **Currency mismatch**: Uses `$` for all prices while every other screen uses `৳`. |
| 4 | **HIGH** | `smart_search_screen.dart` | **Dietary filters are broken**: `_selectedDietary` set is populated by the UI filter chips but is **never checked** in `_applyFilters()`. Only cuisine, rating, and price filters are applied. |
| 5 | **HIGH** | `review_screen.dart` | **Photo upload is broken**: Photo is captured via `ImagePicker` and stored in `_photo` but is **never passed** to `service.addReview()`. The photo is silently discarded. |
| 6 | **HIGH** | `checkout_screen.dart` (customer) | **Direct Supabase queries** in `_deleteOrder()` bypass the service layer, directly deleting from `order_items`, `payments`, and `orders` tables. This is a security/architecture concern. |
| 7 | **HIGH** | `restaurant_reviews_screen.dart` | **Uses FutureBuilder instead of Riverpod** — the reviews list won't auto-refresh after the owner responds to a review. User must manually leave and return. |

---

## 2. Auth Screens

### `signin_screen.dart`
- **Providers**: `authNotifierProvider`
- **Routes**: `/home`, `/driver-dashboard`, `/restaurant-dashboard`, `/admin-dashboard`, `/forgot-password`, `/signup` — ✅ all exist
- **Issues**: None

### `signup_screen.dart`
- **Providers**: `authNotifierProvider`
- **Routes**: Post-signup routes based on role — ✅ all exist
- **Issues**: None

### `forgot_password_screen.dart`
- **Providers**: `authNotifierProvider`
- **Service calls**: `authNotifierProvider.notifier.resetPassword()`
- **Issues**: None

### `role_selection_screen.dart`
- **Routes**: `/signup`, `/signin` — ✅ exist
- **Issues**:
  - ⚠️ **Only shows "Customer" role** card. No way to sign up as driver, restaurant owner, or admin. These roles can only be created by the admin dashboard.

---

## 3. Customer Screens

### `main_navigation_screen.dart`
- **Providers**: `allRestaurantsProvider`, `restaurantSearchProvider`, `currentUserIdProvider`, `userOrdersProvider`
- **Routes**: `/all-restaurants`, `/order-tracking`, `/restaurant-detail` — ✅ exist
- **Issues**:
  - ⚠️ Unused import: `intl` (not used directly in this file)
  - ⚠️ Contains inline `SearchScreen` and `OrdersScreen` classes (large file, could be split)

### `home_screen.dart`
- **Providers**: `currentUserProvider`, `allRestaurantsProvider`, `restaurantSearchProvider`, `newlyAddedRestaurantsProvider`, `topRatedRestaurantsProvider`, `breakfastRestaurantsProvider`, `mustTryRestaurantsProvider`
- **Routes**: `/all-restaurants`, `/restaurant-detail` — ✅ exist
- **Issues**:
  - 🔴 **Empty handler**: Notifications icon `onPressed: () {}` — does nothing
  - 🔴 **Empty handler**: "Deliver to" address `GestureDetector` `onTap: () {}` — does nothing
  - ⚠️ **Hardcoded promo**: Banner text "50% OFF on first order" is static, not sourced from backend promo system
  - ⚠️ References `assets/icons/food_delivery.png` with error fallback

### `cart_screen.dart`
- **Providers**: `cartProvider`, `cartSubtotalProvider`, `restaurantByIdProvider`
- **Routes**: `/checkout` — ✅ exists
- **Issues**:
  - 🔴 **Empty handler**: Promo code "Apply" button `onTap: () {}` — does nothing (promo logic exists in checkout_screen instead)
  - ⚠️ **Hardcoded tax**: `tax = subtotal * 0.1` (10%) — should come from config/backend

### `restaurant_detail_screen.dart` (customer version)
- **Providers**: `restaurantMenuProvider`, `currentUserIdProvider`, `isFavoriteProvider`, `favoritesServiceProvider`, `favoriteRestaurantsProvider`, `cartProvider`
- **Routes**: `/cart` — ✅ exists
- **Issues**:
  - 🔴 **Empty handler**: Footer cart icon `OutlinedButton` `onPressed: () {}` — should navigate to cart or show count
  - ✅ Properly handles different-restaurant cart replacement dialog

### `order_tracking_screen.dart` (customer version)
- **Providers**: `orderByIdProvider`, `userOrdersProvider`, `orderRealtimeStreamProvider`, `driverLocationStreamProvider`
- **Routes**: `/review`, `/chat` — ✅ exist
- **Issues**:
  - ⚠️ **Dart pattern**: `error: (_, _)` uses duplicate underscore for different error parameters — may cause warnings in some Dart 3+ analyzers

### `order_history_screen.dart`
- **Providers**: `userOrdersProvider`, `currentUserIdProvider`
- **Routes**: `/order-tracking`, `/review` — ✅ exist
- **Issues**: None significant. Uses `RateAndTipDriverSheet` widget correctly.

### `profile_screen.dart`
- **Providers**: `currentUserProvider`, `currentUserIdProvider`, `userOrdersProvider`, `authNotifierProvider`
- **Routes**: `/order-history`, `/favorites`, `/address-book`, `/referrals`, `/loyalty`, `/role-selection`
- **Issues**:
  - 🔴 **Empty handler**: Phone Number tile `onTap: () {}` — no edit functionality
  - 🔴 **Empty handler**: Address tile `onTap: () {}` — should navigate to `/address-book`
  - 🔴 **Empty handler**: Payment Methods tile `onTap: () {}` — no implementation at all
  - 🔴 **Empty handler**: Notifications settings tile `onTap: () {}` — should navigate to `/notifications`
  - 🔴 **Empty handler**: Language & Region tile `onTap: () {}` — no implementation
  - 🔴 **No handler**: Camera icon on avatar has no `onTap` — can't change profile photo
  - 🔴 **CRITICAL**: Logout navigates to `/role-selection` which does NOT exist in `main.dart` routes

### `all_restaurants_screen.dart`
- **Providers**: `allRestaurantsProvider`, `restaurantSearchProvider`
- **Routes**: `/restaurant-detail` — ✅ exists
- **Issues**: None

### `notifications_screen.dart`
- **Providers**: `currentUserIdProvider`, `notificationNotifierProvider`
- **Features**: Supabase Realtime subscription for live notifications
- **Issues**: None

### `loyalty_screen.dart`
- **Providers**: `currentUserIdProvider`, `loyaltyAccountProvider`, `loyaltyTransactionsProvider`
- **Issues**:
  - ⚠️ **Missing feature**: No "Redeem Points" button — user can only view balance and history. Redemption only happens at checkout.

### `address_book_screen.dart`
- **Providers**: `currentUserIdProvider`, `userAddressesProvider`, `addressServiceProvider`
- **Issues**:
  - ⚠️ **Missing feature**: No "Edit" existing address — only Add, Set Default, Delete

### `favorites_screen.dart`
- **Providers**: `currentUserProvider`, `favoriteRestaurantsProvider`, `favoritesServiceProvider`
- **Routes**: `/restaurant-detail` — ✅ exists
- **Issues**: None

### `referral_screen.dart`
- **Providers**: `currentUserProvider`, `referralCodeProvider`, `referralStatsProvider`, `referredUsersProvider`
- **Issues**:
  - ⚠️ **Missing feature**: No "Share" button to share referral code via platform share sheet — only copy to clipboard

### `smart_search_screen.dart`
- **Providers**: `allRestaurantsProvider`
- **Routes**: `/restaurant-detail` — ✅ exists
- **Issues**:
  - 🔴 **BUG**: Dietary filters (`_selectedDietary`) collected in UI but **never applied** in `_applyFilters()` — only cuisine, rating, and price filters work
  - ⚠️ **Performance**: Fetches ALL restaurants then filters client-side. Server-side filtering would be better.

### `review_screen.dart`
- **Providers**: `orderServiceProvider`
- **Service calls**: `service.addReview(orderId, rating, review, foodRating, deliveryRating, packagingRating)`
- **Issues**:
  - 🔴 **BUG**: Photo captured via `ImagePicker` and stored in `_photo` but **never passed** to `service.addReview()` — the service method doesn't accept a photo parameter

### `restaurant_reviews_screen.dart`
- **Providers**: `currentUserIdProvider`, `restaurantServiceProvider`
- **Issues**:
  - 🔴 **BUG**: Uses `FutureBuilder` instead of Riverpod for reviews list — no auto-refresh when owner responds
  - 🔴 **Memory leak**: `TextEditingController` created inside `_showRespondDialog()` method with listener added but never properly disposed

### `checkout_screen.dart` (customer)
- **Providers**: `cartProvider`, `cartSubtotalProvider`, `currentUserProvider`, `currentUserIdProvider`, `restaurantByIdProvider`, `appliedPromoProvider`, `redeemPointsProvider`, `loyaltyAccountProvider`, `selectedAddressProvider`, `userAddressesProvider`, `orderServiceProvider`, `paymentServiceProvider`, `promoServiceProvider`, `loyaltyServiceProvider`
- **Routes**: `/address-book` — ✅ exists, pushes to `WiPayPaymentScreen` and `OrderSuccessScreen` via MaterialPageRoute
- **Issues**:
  - 🔴 **Currency mismatch**: Driver tip preset chips use `$` (`'\$${amount.toStringAsFixed(0)}'`), custom tip field uses `\$ ` prefix, tip summary row shows `\$` — but all other amounts use `৳`
  - ⚠️ **Hardcoded 10% tax**: `tax = subtotal * 0.1`
  - ⚠️ **Hardcoded delivery fee fallback**: `restaurantAsync.valueOrNull?.deliveryFee ?? 50.0`
  - ⚠️ **Direct Supabase access**: `_deleteOrder()` directly queries `order_items`, `payments`, `orders` tables instead of going through service layer
  - ✅ Promo code validation properly implemented (unlike cart_screen's empty handler)
  - ✅ Loyalty points redemption and earning work
  - ✅ WiPay card payment integration with proper cleanup on failure

### `order_success_screen.dart`
- **Dependencies**: `confetti` package
- **Issues**:
  - ⚠️ Auto-navigates home after 3.5 seconds — no way for user to go to order tracking instead

---

## 4. Driver Screens

### `driver_dashboard_screen.dart`
- **Providers**: `authNotifierProvider`, `currentUserIdProvider`, `driverProfileProvider`, `driverServiceProvider`
- **Routes**: `/available-orders`, `/active-deliveries`, `/delivery-history`, `/driver-earnings`, `/driver-profile`, `/driver-leaderboard` — ✅ all exist
- **Issues**: None significant. Has driver profile creation flow for new drivers.

### `available_orders_screen.dart`
- **Providers**: `currentUserIdProvider`, `availableOrdersProvider`, `driverProfileProvider`
- **Issues**:
  - 🔴 **Anti-pattern**: `_OrderCard` widget takes `WidgetRef ref` as constructor parameter instead of extending `ConsumerWidget`
  - 🔴 **Currency mismatch**: Uses `$` (dollar sign) while every other screen (except checkout tips) uses `৳`
  - ⚠️ Decline button just invalidates provider — no server-side tracking of declined orders

### `active_deliveries_screen.dart`
- **Providers**: `currentUserIdProvider`, `driverProfileProvider`, `activeDeliveriesProvider`, `locationServiceProvider`, `isTrackingProvider`, `driverServiceProvider`
- **Issues**: None. Feature-rich with GPS toggle, status updates, delivery proof navigation.

### `delivery_history_screen.dart`
- **Providers**: `currentUserIdProvider`, `driverProfileProvider`, `deliveryHistoryProvider`
- **Issues**: None

### `driver_profile_screen.dart`
- **Providers**: `authNotifierProvider`, `currentUserIdProvider`, `driverProfileProvider`, `driverServiceProvider`
- **Routes**: `/role-selection` — 🔴 DOES NOT EXIST
- **Issues**:
  - 🔴 **CRITICAL**: Logout navigates to `/role-selection` which is not in `main.dart` routes
  - 🔴 **Hardcoded stat**: Completion rate shows `98%` if any deliveries exist, `0%` otherwise — not calculated from actual data

### `driver_earnings_screen.dart`
- **Providers**: `currentUserIdProvider`, `driverProfileProvider`, `deliveryHistoryProvider`
- **Issues**:
  - 🔴 **Hardcoded value**: `feePerDelivery = 50.0` is hardcoded — should come from backend or config
  - ⚠️ All earnings calculated as `deliveryCount × 50.0` rather than actual payment data

### `delivery_proof_screen.dart`
- **Providers**: `driverServiceProvider`
- **Service calls**: `service.verifyDeliveryOtp()`, `service.completeDelivery()`
- **Issues**: None. Functional 4-digit OTP verification.

### `driver_leaderboard_screen.dart`
- **Providers**: `driverLeaderboardProvider` (from `premium_providers`)
- **Issues**: None. Display-only.

---

## 5. Restaurant Screens

### `restaurant_dashboard_screen.dart`
- **Providers**: `authNotifierProvider`, `currentUserIdProvider`, `restaurantByOwnerProvider`, `restaurantServiceProvider`, `restaurantOrdersProvider`
- **Routes**: `/menu-management`, `/restaurant-orders`, `/restaurant-settings`, `/restaurant-analytics`, `/restaurant-reviews` — ✅ all exist
- **Issues**:
  - Has restaurant creation flow for new restaurant owners — functional

### `restaurant_order_management_screen.dart`
- **Providers**: `currentUserIdProvider`, `restaurantByOwnerProvider`, `restaurantOrdersProvider`, `orderServiceProvider`
- **Issues**: None significant. Proper tab-based order management with status updates.

### `menu_management_screen.dart`
- **Providers**: `currentUserIdProvider`, `restaurantByOwnerProvider`, `restaurantMenuProvider`, `menuServiceProvider`
- **Service calls**: `menuService.addMenuItem()`, `menuService.deleteMenuItem()`
- **Issues**:
  - ⚠️ **Type safety**: `_AddMenuItemDialog` and `_ManageSidesDialog` accept `dynamic menuService` parameter instead of typed service
  - ⚠️ **Missing feature**: No "Edit" existing menu item name/price — only Add, Delete, and Manage Sides
  - ⚠️ **Missing feature**: No way to toggle item availability (isAvailable) from the list — only shown as badge

### `restaurant_analytics_screen.dart`
- **Providers**: `currentUserIdProvider`, `restaurantByOwnerProvider`, `restaurantOrdersProvider`
- **Issues**:
  - ⚠️ **Performance**: All analytics computed client-side from full order list. For large order volumes, this will be slow. Server-side aggregation would scale better.
  - ✅ Has period filter (Today/7 Days/30 Days/All Time)
  - ✅ Revenue bar chart, order breakdown, top selling items

### `restaurant_settings_screen.dart`
- **Providers**: `currentUserIdProvider`, `restaurantByOwnerProvider`, `restaurantServiceProvider`, `authNotifierProvider`
- **Service calls**: `restaurantService.updateRestaurant()`
- **Issues**:
  - ⚠️ `_prefillFields()` uses `dynamic restaurant` parameter — loses type safety
  - ✅ Full settings editing with save functionality
  - ✅ Sign out properly implemented (no `/role-selection` bug here — just calls `signOut()`)

---

## 6. Admin Screens

### `admin_dashboard_screen.dart`
- **Providers**: `dashboardSummaryProvider`, `currentUserProvider`, `authNotifierProvider`
- **Routes**: `/admin-users`, `/admin-restaurants`, `/admin-drivers`, `/admin-promos`, `/admin-chats` — ✅ all exist
- **Issues**:
  - ✅ Has create user dialog for driver/restaurant roles
  - ✅ Proper revenue, user, restaurant, driver, order stats

### `admin_users_screen.dart`
- **Providers**: `allUsersProvider`, `usersByRoleProvider`, `userSearchProvider`, `adminServiceProvider`
- **Service calls**: `adminService.toggleUserStatus()`
- **Issues**: None. Full user management with search, filter by role, ban/unban.

### `admin_restaurants_screen.dart`
- **Providers**: `allRestaurantsAdminProvider`, `pendingRestaurantsProvider`, `adminServiceProvider`, `restaurantStatisticsProvider`
- **Service calls**: `adminService.verifyRestaurant()`
- **Issues**:
  - ⚠️ **Anti-pattern**: `_RestaurantList` widget takes `WidgetRef ref` as constructor parameter instead of extending `ConsumerWidget`
  - ✅ Verify/reject functionality works correctly

### `admin_drivers_screen.dart`
- **Providers**: `allDriversAdminProvider`, `pendingDriversProvider`, `adminServiceProvider`, `driverStatisticsProvider`
- **Service calls**: `adminService.verifyDriver()`
- **Issues**:
  - ⚠️ **Anti-pattern**: `_DriverList` and `_CreateDriverDialog` take `WidgetRef ref` as constructor parameter

### `admin_promos_screen.dart`
- **Providers**: `allPromosProvider`, `promoServiceProvider`
- **Service calls**: `promoService.toggleActive()`, `promoService.deletePromo()`, `promoService.createPromo()`
- **Issues**: None significant. Full CRUD for promo codes.

### `admin_chats_screen.dart`
- **Providers**: `allChatSummariesProvider`, `allIssuesProvider`
- **Routes**: `/chat` — ✅ exists
- **Issues**: None

---

## 7. Shared Screens

### `chat_screen.dart`
- **Providers**: `currentUserIdProvider`, `currentUserProvider`, `chatMessagesProvider`, `chatServiceProvider`
- **Service calls**: `chatService.sendMessage()`, `chatService.markRead()`
- **Issues**:
  - ⚠️ **Performance**: `markRead()` is called on every `build()` invocation. Should be called once in `initState` or via a side-effect, not during the build phase which can fire many times.

### `main_navigation_screen.dart`
- (Covered in Customer Screens section above)

---

## 8. Legacy Screens (lib/screens/user/)

These 5 files in `lib/screens/user/` appear to be **older/duplicate versions** of screens that now exist in `lib/screens/customer/`. They are simpler, less polished, and may be dead code unless referenced elsewhere.

### `user/checkout_screen.dart`
- **Differences from customer version**: Uses 5% tax (vs 10%), hardcodes `deliveryFee = 50.0`, no promo/loyalty/WiPay integration, no contactless delivery
- **Issues**:
  - ⚠️ Likely dead code — the main `main.dart` route for `/checkout` points to the customer version

### `user/restaurant_detail_screen.dart`
- **Issues**:
  - ⚠️ Simpler version of `customer/restaurant_detail_screen.dart`. Cart button navigates to `/checkout` instead of `/cart`.
  - ⚠️ Likely dead code

### `user/restaurant_listing_screen.dart`
- **Providers**: `restaurantSearchProvider`, `restaurantsByCuisineProvider`
- **Issues**:
  - ⚠️ Likely dead code — replaced by `all_restaurants_screen.dart` and `smart_search_screen.dart`

### `user/order_tracking_screen.dart`
- **Issues**:
  - ⚠️ Much simpler than `customer/order_tracking_screen.dart`. No map, no real-time, no chat.
  - ⚠️ Likely dead code

### `user/user_profile_screen.dart`
- **Providers**: `authNotifierProvider`, `currentUserIdProvider`
- **Issues**:
  - 🔴 Logout navigates to `/role-selection` which does NOT exist
  - ⚠️ Overwrites text controller values on every build (should use `_hasInitialized` pattern like restaurant_settings_screen)
  - ⚠️ Likely dead code — replaced by `customer/profile_screen.dart`

---

## 9. Summary Tables

### Empty `onPressed` / `onTap` Handlers (Broken Buttons)

| File | Widget | Expected Behavior |
|------|--------|-------------------|
| `home_screen.dart` | Notifications icon button | Navigate to `/notifications` |
| `home_screen.dart` | "Deliver to" GestureDetector | Navigate to `/address-book` or show address picker |
| `cart_screen.dart` | Promo "Apply" button | Validate promo code (logic exists in checkout instead) |
| `restaurant_detail_screen.dart` | Cart icon OutlinedButton | Navigate to `/cart` |
| `profile_screen.dart` | Phone Number tile | Show phone edit dialog |
| `profile_screen.dart` | Address tile | Navigate to `/address-book` |
| `profile_screen.dart` | Payment Methods tile | Show payment methods (not implemented) |
| `profile_screen.dart` | Notifications tile | Navigate to `/notifications` |
| `profile_screen.dart` | Language & Region tile | Show language/region settings (not implemented) |
| `profile_screen.dart` | Camera icon on avatar | Show image picker for profile photo |

### Hardcoded / Mock Data

| File | What's Hardcoded | Impact |
|------|-----------------|--------|
| `home_screen.dart` | "50% OFF on first order" promo banner | Not connected to promo system |
| `cart_screen.dart` | 10% tax rate | Should come from config or backend |
| `checkout_screen.dart` | 10% tax rate | Should come from config or backend |
| `checkout_screen.dart` | ৳50 delivery fee fallback | Should always come from restaurant data |
| `driver_earnings_screen.dart` | ৳50 per delivery fee | Earnings should come from actual payment data |
| `driver_profile_screen.dart` | 98% completion rate | Should be calculated from delivery data |
| `user/checkout_screen.dart` | 5% tax rate, ৳50 delivery fee | Legacy file with different hardcoded values |

### Currency Inconsistencies

| File | Uses | Should Use |
|------|------|------------|
| `available_orders_screen.dart` | `$` (all prices) | `৳` |
| `checkout_screen.dart` | `$` (driver tip only) | `৳` |
| `user/restaurant_listing_screen.dart` | `tk` suffix | `৳` |

### Anti-Patterns (WidgetRef as Constructor Parameter)

These widgets pass `WidgetRef` as a constructor parameter instead of extending `ConsumerWidget`/`ConsumerStatefulWidget`:

| File | Widget |
|------|--------|
| `available_orders_screen.dart` | `_OrderCard` |
| `admin_restaurants_screen.dart` | `_RestaurantList` |
| `admin_drivers_screen.dart` | `_DriverList` |
| `admin_drivers_screen.dart` | `_CreateDriverDialog` |

### Missing Route

| Route | Used By | Status |
|-------|---------|--------|
| `/role-selection` | `profile_screen.dart`, `driver_profile_screen.dart`, `user/user_profile_screen.dart` | ❌ **NOT DEFINED in main.dart** |

### Missing Features

| Screen | Missing Feature |
|--------|----------------|
| `loyalty_screen.dart` | No "Redeem Points" button (only at checkout) |
| `address_book_screen.dart` | No "Edit" existing address |
| `referral_screen.dart` | No "Share" button via platform share sheet |
| `menu_management_screen.dart` | No "Edit" existing menu item |
| `menu_management_screen.dart` | No toggle for item availability |
| `role_selection_screen.dart` | Only Customer role — no driver/restaurant sign-up path |
| `review_screen.dart` | Photo upload captured but never sent |
| `order_success_screen.dart` | No "Track Order" button (auto-redirects home) |

### Type Safety Issues

| File | Issue |
|------|-------|
| `menu_management_screen.dart` | `_AddMenuItemDialog.menuService` typed as `dynamic` |
| `menu_management_screen.dart` | `_ManageSidesDialog.menuService` typed as `dynamic` |
| `restaurant_settings_screen.dart` | `_prefillFields()` takes `dynamic restaurant` |
| `main.dart` | `settings.arguments as dynamic` cast for restaurant-detail route |

### Performance Concerns

| File | Issue |
|------|-------|
| `smart_search_screen.dart` | Fetches ALL restaurants then filters client-side |
| `restaurant_analytics_screen.dart` | All analytics computed client-side from full order list |
| `chat_screen.dart` | `markRead()` called on every `build()` |

---

## Total Issues Found

| Category | Count |
|----------|-------|
| Critical/High bugs | 7 |
| Empty button handlers | 10 |
| Hardcoded values | 7 |
| Currency inconsistencies | 3 |
| Anti-patterns (ref passing) | 4 |
| Missing routes | 1 |
| Missing features | 8 |
| Type safety issues | 4 |
| Performance concerns | 3 |
| Legacy dead code files | 5 |
| **Total** | **52** |
