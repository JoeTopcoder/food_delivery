import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:food_driver/models/user_model.dart';
import 'package:food_driver/models/restaurant_model.dart';
import 'package:food_driver/models/driver_model.dart';
import 'package:food_driver/models/promo_model.dart';
import 'package:food_driver/models/refund_model.dart';
import 'package:food_driver/models/earning_model.dart';
import 'package:food_driver/services/social/analytics_service.dart';
import 'package:food_driver/services/payment/payout_service.dart';
import 'package:food_driver/providers/auth_provider.dart';
import 'package:food_driver/providers/admin_provider.dart';

// ── Shared mock data ──────────────────────────────────────────────────────────

final testAdminUser = User(
  id: 'admin-user-1',
  email: 'admin@mealhub.com',
  name: 'Test Admin',
  role: 'admin',
  isActive: true,
  onboardingCompleted: true,
  createdAt: DateTime(2024, 1, 1),
);

final mockDashboard = <String, dynamic>{
  'total_users': 120,
  'total_restaurants': 18,
  'total_drivers': 45,
  'total_orders': 630,
  'pending_restaurants': 2,
  'pending_drivers': 3,
  'total_revenue': 8500.0,
  'today_orders': 30,
  'today_revenue': 410.0,
  'active_orders': 7,
  'revenue_this_month': 12000.0,
};

List<User> mockUsers() => [
  User(
    id: 'u1',
    email: 'alice@example.com',
    name: 'Alice Smith',
    role: 'customer',
    isActive: true,
    onboardingCompleted: true,
    createdAt: DateTime(2024, 3, 10),
  ),
  User(
    id: 'u2',
    email: 'bob@example.com',
    name: 'Bob Jones',
    role: 'driver',
    isActive: false,
    onboardingCompleted: true,
    createdAt: DateTime(2024, 2, 5),
  ),
];

List<Restaurant> mockRestaurants() => [
  Restaurant(
    id: 'rest-0001-aaaa-bbbb',
    ownerId: 'user-0003-cccc-dddd',
    name: 'Burger Palace',
    isOpen: true,
    isVerified: true,
    storeType: 'food',
    status: 'active',
    onboardingStep: 5,
    createdAt: DateTime(2024, 1, 20),
  ),
  Restaurant(
    id: 'rest-0002-eeee-ffff',
    ownerId: 'user-0004-gggg-hhhh',
    name: 'Pizza Town',
    isOpen: false,
    isVerified: false,
    storeType: 'food',
    status: 'draft',
    onboardingStep: 2,
    createdAt: DateTime(2024, 3, 1),
  ),
];

List<Driver> mockDrivers() => [
  Driver(
    id: 'drv-0001-aaaa-bbbb',
    userId: 'usr-0005-cccc-dddd',
    fullName: 'Jane Driver',
    rating: 4.8,
    completedDeliveries: 120,
    isAvailable: true,
    isVerified: true,
    driverStatus: 'approved',
    serviceType: 'food_delivery',
    isFoodDriverApproved: true,
    isRideDriverApproved: false,
    isAvailableForFood: true,
    isAvailableForRides: false,
    isOnline: true,
    createdAt: DateTime(2024, 2, 1),
  ),
  Driver(
    id: 'drv-0002-eeee-ffff',
    userId: 'usr-0006-gggg-hhhh',
    fullName: 'Sam Pending',
    rating: 3.5,
    completedDeliveries: 45,
    isAvailable: false,
    isVerified: false,
    driverStatus: 'pending_review',
    serviceType: 'food_delivery',
    isFoodDriverApproved: false,
    isRideDriverApproved: false,
    isAvailableForFood: false,
    isAvailableForRides: false,
    isOnline: false,
    createdAt: DateTime(2024, 4, 15),
  ),
];

List<PromoCode> mockPromos() => [
  PromoCode(
    id: 'promo-0001-aaaa',
    code: 'SAVE10',
    discountType: 'percentage',
    discountValue: 10.0,
    usedCount: 25,
    isActive: true,
    createdAt: DateTime(2024, 1, 1),
  ),
];

// orderId must be ≥ 8 chars — the disputes screen truncates to first 8.
List<Refund> mockRefunds() => [
  Refund(
    id: 'refund-0001-aaaa-bbbb',
    orderId: 'order-0001-aaaa-bbbb',
    userId: 'user-0001-cccc-dddd',
    amount: 15.50,
    reason: 'Order was incorrect',
    status: 'pending',
    createdAt: DateTime(2024, 5, 1),
  ),
];

List<EarningAccount> mockEarningAccounts() => [
  EarningAccount(
    id: 'earn-0001-aaaa-bbbb',
    userId: 'user-0001-cccc-dddd',
    userName: 'Alice Smith',
    tier: 'builder',
    totalEarned: 120.0,
    totalDirectRefs: 5,
    totalIndirectRefs: 12,
    totalOrdersGenerated: 30,
    monthlyEarned: 20.0,
    monthlyOrders: 8,
    monthKey: '2024-05',
    createdAt: DateTime(2024, 1, 1),
    updatedAt: DateTime(2024, 5, 1),
  ),
];

List<PayoutRequest> mockPayouts() => [
  PayoutRequest(
    id: 'payout-0001-aaaa-bbbb',
    requesterId: 'drv-0001-aaaa-bbbb',
    requesterType: 'driver',
    amount: 200.0,
    bankName: 'FirstCaribbean',
    bankAccountNumber: '****1234',
    bankAccountHolder: 'John Doe',
    status: 'pending',
    createdAt: DateTime(2024, 5, 10),
  ),
];

AnalyticsSummary mockAnalyticsSummary() => const AnalyticsSummary(
  dau: 88,
  newUsers: 12,
  ordersToday: 42,
  revenueToday: 520.0,
  aovToday: 12.38,
  ordersWeek: 290,
  revenueWeek: 3600.0,
  ordersMonth: 1200,
  revenueMonth: 15000.0,
  completionRate: 91.5,
);

// ── Provider overrides ────────────────────────────────────────────────────────

/// Returns overrides that mock all Supabase-dependent providers so widgets
/// can render without a live Supabase connection.
List<Override> adminCoreOverrides() => [
  // Auth
  currentUserProvider.overrideWith((ref) => testAdminUser),

  // Dashboard
  dashboardSummaryProvider.overrideWith((ref) async => mockDashboard),
  adminNewOrderRealtimeProvider.overrideWith((ref) {}),
  adminPendingRealtimeProvider.overrideWith((ref) {}),

  // Users
  allUsersProvider.overrideWith((ref, params) async => mockUsers()),
  usersByRoleProvider.overrideWith((ref, role) async => mockUsers()),
  userSearchProvider.overrideWith((ref, query) async => mockUsers()),
  userStatisticsProvider.overrideWith(
    (ref) async => <String, dynamic>{
      'total_users': 120,
      'customers': 85,
      'drivers': 25,
      'restaurants': 10,
    },
  ),

  // Restaurants
  allRestaurantsAdminProvider.overrideWith(
    (ref, params) async => mockRestaurants(),
  ),
  pendingRestaurantsProvider.overrideWith((ref) async => mockRestaurants()),
  rejectedRestaurantsProvider.overrideWith((ref) async => []),
  restaurantStatisticsProvider.overrideWith(
    (ref) async => <String, dynamic>{
      'total': 18,
      'verified': 14,
      'pending': 2,
      'rejected': 2,
    },
  ),

  // Drivers
  allDriversAdminProvider.overrideWith(
    (ref, params) async => mockDrivers(),
  ),
  pendingDriversProvider.overrideWith((ref) async => mockDrivers()),
  approvedDriversProvider.overrideWith((ref) async => mockDrivers()),
  rejectedDriversProvider.overrideWith((ref) async => []),
  driverStatisticsProvider.overrideWith(
    (ref) async => <String, dynamic>{
      'total': 45,
      'approved': 38,
      'pending': 4,
      'rejected': 3,
    },
  ),

  // Financials
  financialStatisticsProvider.overrideWith(
    (ref) async => <String, dynamic>{
      'total_revenue': 85000.0,
      'this_month': 12000.0,
      'total_commission': 8500.0,
      'pending_payouts': 1200.0,
    },
  ),
  revenueStatisticsProvider.overrideWith(
    (ref) async => <String, dynamic>{
      'daily': 410.0,
      'weekly': 2800.0,
      'monthly': 12000.0,
    },
  ),
  orderStatisticsProvider.overrideWith(
    (ref) async => <String, dynamic>{
      'total': 630,
      'completed': 580,
      'cancelled': 50,
    },
  ),
];

// ── Supabase test initializer ─────────────────────────────────────────────────

/// Call in [setUpAll] for any test file that renders widgets which access
/// [SupabaseConfig.client] directly (e.g. screens with private providers
/// that are not overrideable via Riverpod).
Future<void> setupTestSupabase() async {
  try {
    Supabase.instance.client; // already initialized — nothing to do
    return;
  } catch (_) {}
  // Supabase.initialize uses shared_preferences for auth token storage.
  // In widget tests there is no native channel, so we stub it out first.
  SharedPreferences.setMockInitialValues({});
  await Supabase.initialize(
    url: 'https://placeholder-test.supabase.co',
    // Minimal valid-format anon key (unsigned, fake secret — test-only)
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
        '.eyJyb2xlIjoiYW5vbiIsImlhdCI6MTYwMDAwMDAwMH0'
        '.placeholder_test_signature',
  );
}

// ── Widget builder ────────────────────────────────────────────────────────────

/// Wraps [child] in a [ProviderScope] + [MaterialApp] with full locale support.
Widget buildAdminTestApp(
  Widget child, {
  List<Override> extraOverrides = const [],
}) {
  return ProviderScope(
    overrides: [
      ...adminCoreOverrides(),
      ...extraOverrides,
    ],
    child: MaterialApp(
      home: child,
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  );
}
