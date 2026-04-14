import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'config/supabase_config.dart';
import 'services/app_config_service.dart';
import 'models/restaurant_model.dart';
import 'models/order_model.dart';
import 'providers/auth_provider.dart';
import 'providers/notification_provider.dart';
import 'services/notification_service.dart';
import 'config/app_constants.dart';
import 'screens/auth/signin_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/role_selection_screen.dart';
import 'screens/driver/driver_dashboard_screen.dart';
import 'screens/driver/available_orders_screen.dart';
import 'screens/driver/active_deliveries_screen.dart';
import 'screens/driver/delivery_history_screen.dart';
import 'screens/driver/driver_profile_screen.dart';
import 'screens/admin/admin_dashboard_screen.dart';
import 'screens/admin/admin_users_screen.dart';
import 'screens/admin/admin_restaurants_screen.dart';
import 'screens/admin/admin_drivers_screen.dart';
import 'screens/customer/home_screen.dart';
import 'screens/customer/all_restaurants_screen.dart';
import 'screens/customer/restaurant_detail_screen.dart';
import 'screens/customer/cart_screen.dart';
import 'screens/customer/grocery_cart_screen.dart';
import 'screens/customer/checkout_screen.dart';
import 'screens/customer/grocery_checkout_screen.dart';
import 'screens/customer/order_tracking_screen.dart';
import 'screens/customer/profile_screen.dart';
import 'screens/customer/review_screen.dart';
import 'screens/customer/notifications_screen.dart';
import 'screens/customer/loyalty_screen.dart';
import 'screens/customer/address_book_screen.dart';
import 'screens/customer/order_history_screen.dart';
import 'screens/customer/referral_screen.dart';
import 'screens/customer/favorites_screen.dart';
import 'screens/customer/smart_search_screen.dart';
import 'screens/customer/restaurant_reviews_screen.dart';
import 'screens/driver/driver_leaderboard_screen.dart';
import 'screens/shared/chat_screen.dart';
import 'screens/shared/call_screen.dart';
import 'models/chat_model.dart';
import 'screens/driver/driver_earnings_screen.dart';
import 'screens/admin/admin_promos_screen.dart';
import 'screens/admin/admin_chats_screen.dart';
import 'screens/admin/admin_payouts_screen.dart';
import 'screens/admin/admin_financials_screen.dart';
import 'screens/admin/admin_disputes_screen.dart';
import 'screens/admin/admin_feedback_screen.dart';
import 'screens/admin/admin_surge_screen.dart';
import 'screens/admin/admin_banners_screen.dart';
import 'screens/admin/admin_orders_screen.dart';
import 'screens/admin/admin_lookup_screen.dart';
import 'screens/admin/admin_contract_screen.dart';
import 'screens/admin/admin_regions_screen.dart';
import 'screens/admin/admin_ads_screen.dart';
import 'widgets/incoming_call_listener.dart';
import 'screens/customer/refund_dispute_screen.dart';
import 'screens/customer/group_order_screen.dart';
import 'screens/customer/subscription_screen.dart';
import 'screens/customer/feedback_screen.dart';
import 'screens/customer/wallet_screen.dart';
import 'screens/restaurant/restaurant_dashboard_screen.dart';
import 'screens/restaurant/restaurant_order_management_screen.dart';
import 'screens/restaurant/restaurant_analytics_screen.dart';
import 'screens/restaurant/restaurant_settings_screen.dart';
import 'screens/restaurant/menu_management_screen.dart';
import 'screens/restaurant/grocery_management_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'screens/splash_screen.dart';
// import 'utils/app_logger.dart';
import 'utils/app_theme.dart';
import 'services/cache_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await SupabaseConfig.initialize();
  await CacheService.init();
  // Load DB-driven config (non-blocking — falls back to compiled defaults on error)
  await AppConfigService(SupabaseConfig.client).load();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();

    // Share navigator key with notification service for tap navigation
    NotificationService.navigatorKey = _navigatorKey;

    ref.listenManual<AuthState>(authNotifierProvider, (previous, next) {
      final wasAuthenticated = previous?.isAuthenticated ?? false;
      final isSignedOut = wasAuthenticated && !next.isAuthenticated;

      if (isSignedOut) {
        _navigatorKey.currentState?.pushNamedAndRemoveUntil(
          '/signin',
          (route) => false,
        );
      }

      // Subscribe to role-specific FCM topics when authenticated
      if (next.isAuthenticated) {
        final role = next.user?.role;
        final userId = next.user?.id;
        if (role == 'driver') {
          NotificationService().subscribeToTopic(
            AppConstants.fcmTopicAvailableDrivers,
          );
        } else if (role == 'restaurant') {
          NotificationService().subscribeToTopic(
            AppConstants.fcmTopicAllRestaurants,
          );
        } else if (role == 'admin') {
          NotificationService().subscribeToTopic(AppConstants.fcmTopicAdmins);
        }
        // All users (especially customers) subscribe to their personal topic
        if (userId != null) {
          NotificationService().subscribeToTopic('customer_$userId');
        }
      }
      // Unsubscribe when signing out
      if (isSignedOut) {
        final userId = previous?.user?.id;
        NotificationService().unsubscribeFromTopic(
          AppConstants.fcmTopicAvailableDrivers,
        );
        NotificationService().unsubscribeFromTopic(
          AppConstants.fcmTopicAllRestaurants,
        );
        NotificationService().unsubscribeFromTopic(AppConstants.fcmTopicAdmins);
        if (userId != null) {
          NotificationService().unsubscribeFromTopic('customer_$userId');
        }
      }
    });
  }

  static Widget _getHomeForRole(String? role) {
    switch (role) {
      case 'driver':
        return const SplashScreen(
          role: 'driver',
          destination: DriverDashboardScreen(),
        );
      case 'restaurant':
        return const SplashScreen(
          role: 'restaurant',
          destination: RestaurantDashboardScreen(),
        );
      case 'admin':
        return const SplashScreen(
          role: 'admin',
          destination: AdminDashboardScreen(),
        );
      default:
        return const SplashScreen(
          role: 'customer',
          destination: MainNavigationScreen(),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    // Initialize notifications
    ref.watch(initNotificationProvider);

    return IncomingCallListener(
      navigatorKey: _navigatorKey,
      child: MaterialApp(
        navigatorKey: _navigatorKey,
        title: 'MealHub',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: authState.isAuthenticated
            ? _getHomeForRole(authState.user?.role)
            : const SignInScreen(),
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/signin':
              return MaterialPageRoute(
                builder: (context) => const SignInScreen(),
              );
            case '/signup':
              final role = settings.arguments as String? ?? 'user';
              return MaterialPageRoute(
                builder: (context) => SignUpScreen(role: role),
              );
            case '/forgot-password':
              return MaterialPageRoute(
                builder: (context) => const ForgotPasswordScreen(),
              );
            case '/home':
              return MaterialPageRoute(
                builder: (context) => const MainNavigationScreen(),
              );
            // Driver Routes
            case '/driver-dashboard':
              return MaterialPageRoute(
                builder: (context) => const DriverDashboardScreen(),
              );
            case '/available-orders':
              return MaterialPageRoute(
                builder: (context) => const AvailableOrdersScreen(),
              );
            case '/active-deliveries':
              return MaterialPageRoute(
                builder: (context) => const ActiveDeliveriesScreen(),
              );
            case '/delivery-history':
              return MaterialPageRoute(
                builder: (context) => const DeliveryHistoryScreen(),
              );
            case '/driver-profile':
              return MaterialPageRoute(
                builder: (context) => const DriverProfileScreen(),
              );
            // Admin Routes
            case '/admin-dashboard':
              return MaterialPageRoute(
                builder: (context) => const AdminDashboardScreen(),
              );
            case '/admin-users':
              return MaterialPageRoute(
                builder: (context) => const AdminUsersScreen(),
              );
            case '/admin-restaurants':
              return MaterialPageRoute(
                builder: (context) => const AdminRestaurantsScreen(),
              );
            case '/admin-drivers':
              return MaterialPageRoute(
                builder: (context) => const AdminDriversScreen(),
              );
            // Customer Routes
            case '/customer-home':
              return MaterialPageRoute(
                builder: (context) => const CustomerHomeScreen(),
              );
            case '/all-restaurants':
              return MaterialPageRoute(
                builder: (context) => const AllRestaurantsScreen(),
              );
            // Restaurant Routes
            case '/restaurant-dashboard':
              return MaterialPageRoute(
                builder: (context) => const RestaurantDashboardScreen(),
              );
            case '/restaurant-orders':
              return MaterialPageRoute(
                builder: (context) => const RestaurantOrderManagementScreen(),
              );
            case '/restaurant-analytics':
              return MaterialPageRoute(
                builder: (context) => const RestaurantAnalyticsScreen(),
              );
            case '/restaurant-settings':
              return MaterialPageRoute(
                builder: (context) => const RestaurantSettingsScreen(),
              );
            case '/menu-management':
              return MaterialPageRoute(
                builder: (context) => const MenuManagementScreen(),
              );
            case '/grocery-management':
              return MaterialPageRoute(
                builder: (context) => const GroceryManagementScreen(),
              );
            case '/restaurant-detail':
              if (settings.arguments is! Restaurant) return null;
              final restaurant = settings.arguments as Restaurant;
              return MaterialPageRoute(
                builder: (context) =>
                    RestaurantDetailScreen(restaurant: restaurant),
              );
            case '/cart':
              return MaterialPageRoute(
                builder: (context) => const CartScreen(),
              );
            case '/grocery-cart':
              return MaterialPageRoute(
                builder: (context) => const GroceryCartScreen(),
              );
            case '/checkout':
              return MaterialPageRoute(
                builder: (context) => const CheckoutScreen(),
              );
            case '/grocery-checkout':
              return MaterialPageRoute(
                builder: (context) => const GroceryCheckoutScreen(),
              );
            case '/order-tracking':
              final orderId = settings.arguments as String?;
              return MaterialPageRoute(
                builder: (context) => OrderTrackingScreen(orderId: orderId),
              );
            case '/customer-profile':
              return MaterialPageRoute(
                builder: (context) => const CustomerProfileScreen(),
              );
            case '/review':
              if (settings.arguments is! Order) return null;
              final order = settings.arguments as Order;
              return MaterialPageRoute(
                builder: (context) => ReviewScreen(order: order),
              );
            case '/notifications':
              return MaterialPageRoute(
                builder: (context) => const NotificationsScreen(),
              );
            case '/loyalty':
              return MaterialPageRoute(
                builder: (context) => const LoyaltyScreen(),
              );
            case '/address-book':
              return MaterialPageRoute(
                builder: (context) => const AddressBookScreen(),
              );
            case '/order-history':
              return MaterialPageRoute(
                builder: (context) => const OrderHistoryScreen(),
              );
            case '/driver-earnings':
              return MaterialPageRoute(
                builder: (context) => const DriverEarningsScreen(),
              );
            case '/admin-promos':
              return MaterialPageRoute(
                builder: (context) => const AdminPromosScreen(),
              );
            case '/admin-chats':
              return MaterialPageRoute(
                builder: (context) => const AdminChatsScreen(),
              );
            case '/admin-payouts':
              return MaterialPageRoute(
                builder: (context) => const AdminPayoutsScreen(),
              );
            case '/admin-financials':
              return MaterialPageRoute(
                builder: (context) => const AdminFinancialsScreen(),
              );
            case '/admin-orders':
              return MaterialPageRoute(
                builder: (context) => const AdminOrdersScreen(),
              );
            case '/chat':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (context) => ChatScreen(
                  orderId: args?['orderId'] as String? ?? '',
                  otherPartyName: args?['otherPartyName'] as String? ?? 'Chat',
                  receiverId: args?['receiverId'] as String?,
                ),
              );
            case '/call':
              final args = settings.arguments as Map<String, dynamic>?;
              final call = args?['call'] as CallRecord?;
              if (call == null) return null;
              final isCaller = args?['isCaller'] as bool? ?? true;
              final otherPartyName = args?['otherPartyName'] as String?;
              return MaterialPageRoute(
                builder: (context) => CallScreen(
                  call: call,
                  isCaller: isCaller,
                  otherPartyName: otherPartyName,
                ),
              );
            case '/referrals':
              return MaterialPageRoute(
                builder: (context) => const ReferralScreen(),
              );
            case '/favorites':
              return MaterialPageRoute(
                builder: (context) => const FavoritesScreen(),
              );
            case '/search':
              return MaterialPageRoute(
                builder: (context) => const SmartSearchScreen(),
              );
            case '/role-selection':
              return MaterialPageRoute(
                builder: (context) => const RoleSelectionScreen(),
              );
            case '/driver-leaderboard':
              return MaterialPageRoute(
                builder: (context) => const DriverLeaderboardScreen(),
              );
            case '/restaurant-reviews':
              final args = settings.arguments as Map<String, dynamic>?;
              return MaterialPageRoute(
                builder: (context) => RestaurantReviewsScreen(
                  restaurantId: args?['restaurantId'] as String? ?? '',
                  restaurantName:
                      args?['restaurantName'] as String? ?? 'Reviews',
                  isOwner: args?['isOwner'] as bool? ?? false,
                ),
              );
            // ── New Feature Routes ──
            case '/refund-dispute':
              return MaterialPageRoute(
                builder: (context) => const RefundDisputeScreen(),
              );
            case '/group-orders':
              return MaterialPageRoute(
                builder: (context) => const GroupOrderScreen(),
              );
            case '/subscriptions':
              return MaterialPageRoute(
                builder: (context) => const SubscriptionScreen(),
              );
            case '/feedback':
              return MaterialPageRoute(
                builder: (context) => const FeedbackScreen(),
              );
            case '/admin-disputes':
              return MaterialPageRoute(
                builder: (context) => const AdminDisputesScreen(),
              );
            case '/admin-feedback':
              return MaterialPageRoute(
                builder: (context) => const AdminFeedbackScreen(),
              );
            case '/admin-surge':
              return MaterialPageRoute(
                builder: (context) => const AdminSurgeScreen(),
              );
            case '/admin-banners':
              return MaterialPageRoute(
                builder: (context) => const AdminBannersScreen(),
              );
            case '/admin-lookup':
              return MaterialPageRoute(
                builder: (context) => const AdminLookupScreen(),
              );
            case '/admin-contract':
              return MaterialPageRoute(
                builder: (context) => const AdminContractScreen(),
              );
            case '/admin-regions':
              return MaterialPageRoute(
                builder: (context) => const AdminRegionsScreen(),
              );
            case '/admin-ads':
              return MaterialPageRoute(
                builder: (context) => const AdminAdsScreen(),
              );
            case '/wallet':
              return MaterialPageRoute(
                builder: (context) => const WalletScreen(),
              );
            default:
              return MaterialPageRoute(
                builder: (context) => const MainNavigationScreen(),
              );
          }
        },
      ),
    );
  }
}

// Note: MainNavigationScreen is now imported from screens/main_navigation_screen.dart
