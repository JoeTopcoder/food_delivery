import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'l10n/app_localizations.dart';
import 'config/supabase_config.dart';
import 'services/app_config_service.dart';
import 'models/restaurant_model.dart';
import 'models/order_model.dart';
import 'providers/auth_provider.dart';
import 'providers/notification_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'services/notification_service.dart';
import 'config/app_constants.dart';
import 'utils/theme_service.dart';
import 'screens/auth/signin_screen.dart';
import 'screens/auth/signup_screen.dart';
import 'screens/auth/forgot_password_screen.dart';
import 'screens/auth/role_selection_screen.dart';
import 'features/auth/screens/auth_launch_gate_screen.dart';
import 'features/customer/screens/customer_onboarding_screen.dart';
import 'features/driver/screens/driver_onboarding_screen.dart';
import 'features/restaurant/screens/restaurant_onboarding_screen.dart';
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
import 'screens/customer/earnings_screen.dart';
import 'screens/driver/driver_referral_screen.dart';
import 'screens/restaurant/restaurant_referral_screen.dart';
import 'screens/customer/favorites_screen.dart';
import 'screens/customer/smart_search_screen.dart';
import 'screens/customer/restaurant_reviews_screen.dart';
import 'screens/driver/driver_leaderboard_screen.dart';
import 'screens/shared/chat_screen.dart';
import 'screens/shared/call_screen.dart';
import 'models/chat_model.dart';
import 'screens/driver/driver_earnings_screen.dart';
import 'screens/driver/driver_wallet_screen.dart';
import 'screens/driver/advanced_earnings_screen.dart';
import 'screens/driver/driver_performance_screen.dart';
import 'screens/driver/demand_heatmap_screen.dart';
import 'screens/admin/admin_promos_screen.dart';
import 'screens/admin/admin_chats_screen.dart';
import 'screens/admin/admin_payouts_screen.dart';
import 'screens/admin/admin_financials_screen.dart';
import 'screens/admin/admin_analytics_screen.dart';
import 'screens/admin/admin_ai_panel_screen.dart';
import 'screens/admin/admin_disputes_screen.dart';
import 'screens/admin/admin_feedback_screen.dart';
import 'screens/admin/admin_surge_screen.dart';
import 'screens/admin/admin_banners_screen.dart';
import 'screens/admin/admin_orders_screen.dart';
import 'screens/admin/admin_lookup_screen.dart';
import 'screens/admin/admin_contract_screen_v2.dart';
import 'screens/admin/admin_regions_screen.dart';
import 'screens/admin/admin_ads_screen.dart';
import 'screens/admin/admin_pricing_screen.dart';
import 'widgets/incoming_call_listener.dart';
import 'screens/splash_screen.dart';
import 'widgets/role_guard.dart';
import 'screens/customer/refund_dispute_screen.dart';
import 'screens/customer/group_order_screen.dart';
import 'screens/customer/group_order_detail_screen.dart';
import 'screens/customer/subscription_screen.dart';
import 'screens/customer/feedback_screen.dart';
import 'screens/customer/wallet_screen.dart';
import 'screens/restaurant/restaurant_dashboard_screen.dart';
import 'screens/restaurant/restaurant_order_management_screen.dart';
import 'screens/restaurant/restaurant_analytics_screen.dart';
import 'screens/restaurant/restaurant_settings_screen.dart';
import 'screens/restaurant/menu_management_screen.dart';
import 'screens/restaurant/grocery_management_screen.dart';
import 'screens/restaurant/restaurant_loyalty_screen.dart';
import 'screens/restaurant/restaurant_offer_screen.dart';
import 'screens/restaurant/restaurant_contract_screen.dart';
import 'screens/admin/admin_loyalty_screen.dart';
import 'screens/admin/admin_earnings_screen.dart';
import 'screens/admin/admin_mealhub_screen.dart';
import 'screens/shared/app_settings_screen.dart';
import 'screens/main_navigation_screen.dart';
import 'utils/app_logger.dart';
import 'utils/app_theme.dart';
import 'services/cache_service.dart';
import 'providers/feature_providers.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Run independent init tasks in parallel
  await Future.wait([
    Firebase.initializeApp(),
    SupabaseConfig.initialize(),
    CacheService.init(),
  ]);

  // Load DB-driven config (depends on Supabase being ready)
  await AppConfigService(SupabaseConfig.client).load();

  // Load remote color theme (non-blocking fallback to defaults)
  await ThemeService.load();

  // Refresh session on startup so we always have a fresh token.
  try {
    await SupabaseConfig.client.auth.refreshSession();
  } catch (_) {
    // Not signed in yet or refresh failed — ignore.
  }
  // Initialize Stripe (non-blocking — don't await applySettings)
  final stripeKey = AppConstants.stripePublishableKey;
  if (stripeKey.isNotEmpty) {
    Stripe.publishableKey = stripeKey;
    Stripe.merchantIdentifier = AppConstants.stripeMerchantId;
    // applySettings runs lazily; no need to block startup
    Stripe.instance.applySettings().catchError((_) {});
  }
  AppLogger.info(
    '[Main] After config load — defaultDeliveryFee=${AppConstants.defaultDeliveryFee}, baseFee=${AppConstants.deliveryBaseFee}',
  );
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

    // Start listening for admin pricing changes in real time
    ref.read(appConfigRealtimeProvider);

    // Share navigator key with notification service for tap navigation
    NotificationService.navigatorKey = _navigatorKey;

    ref.listenManual<AuthState>(authNotifierProvider, (previous, next) {
      final wasAuthenticated = previous?.isAuthenticated ?? false;
      final isSignedOut = wasAuthenticated && !next.isAuthenticated;

      if (isSignedOut) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _navigatorKey.currentState?.pushNamedAndRemoveUntil(
            '/role-selection',
            (route) => false,
          );
        });
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
      case 'customer':
      case 'user':
        return const MainNavigationScreen();
      case 'driver':
        return const DriverDashboardScreen();
      case 'restaurant':
        return const RestaurantDashboardScreen();
      case 'admin':
        return const AdminDashboardScreen();
      default:
        // Unknown/null role must never silently show the customer screen.
        // Return the gate — AuthLaunchGateScreen will sign them out.
        return const AuthLaunchGateScreen();
    }
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
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
        themeMode: themeMode,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const AppLaunchSplash(),
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/':
              return MaterialPageRoute(
                builder: (context) => const AuthLaunchGateScreen(),
              );
            case '/role-selection':
              return MaterialPageRoute(
                builder: (context) => const RoleSelectionScreen(),
              );
            case '/onboarding/customer':
              if (authState.isAuthenticated) {
                return MaterialPageRoute(
                  builder: (context) => _getHomeForRole(authState.user?.role),
                );
              }
              return MaterialPageRoute(
                builder: (context) => const CustomerOnboardingScreen(),
              );
            case '/onboarding/driver':
              if (authState.isAuthenticated) {
                return MaterialPageRoute(
                  builder: (context) => _getHomeForRole(authState.user?.role),
                );
              }
              return MaterialPageRoute(
                builder: (context) => const DriverOnboardingScreen(),
              );
            case '/onboarding/restaurant':
              if (authState.isAuthenticated) {
                return MaterialPageRoute(
                  builder: (context) => _getHomeForRole(authState.user?.role),
                );
              }
              return MaterialPageRoute(
                builder: (context) => const RestaurantOnboardingScreen(),
              );
            case '/join/driver':
              return MaterialPageRoute(
                builder: (context) => const DriverOnboardingScreen(),
              );
            case '/join/restaurant':
              return MaterialPageRoute(
                builder: (context) => const RestaurantOnboardingScreen(),
              );
            case '/signin':
              return MaterialPageRoute(
                builder: (context) => const SignInScreen(),
              );
            case '/signin/customer':
              return MaterialPageRoute(
                builder: (context) => const SignInScreen(role: 'user'),
              );
            case '/signin/driver':
              return MaterialPageRoute(
                builder: (context) => const SignInScreen(role: 'driver'),
              );
            case '/signin/restaurant':
              return MaterialPageRoute(
                builder: (context) => const SignInScreen(role: 'restaurant'),
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
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user', 'customer'],
                  child: MainNavigationScreen(),
                ),
              );
            // Driver Routes
            case '/driver-dashboard':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: DriverDashboardScreen(),
                ),
              );
            case '/available-orders':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: AvailableOrdersScreen(),
                ),
              );
            case '/active-deliveries':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: ActiveDeliveriesScreen(),
                ),
              );
            case '/delivery-history':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: DeliveryHistoryScreen(),
                ),
              );
            case '/driver-profile':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: DriverProfileScreen(),
                ),
              );
            // Admin Routes
            case '/admin-dashboard':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminDashboardScreen(),
                ),
              );
            case '/admin-users':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminUsersScreen(),
                ),
              );
            case '/admin-restaurants':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminRestaurantsScreen(),
                ),
              );
            case '/admin-drivers':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminDriversScreen(),
                ),
              );
            // Customer Routes
            case '/customer-home':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: CustomerHomeScreen(),
                ),
              );
            case '/all-restaurants':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: AllRestaurantsScreen(),
                ),
              );
            // Restaurant Routes
            case '/restaurant-dashboard':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['restaurant'],
                  child: RestaurantDashboardScreen(),
                ),
              );
            case '/restaurant-orders':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['restaurant'],
                  child: RestaurantOrderManagementScreen(),
                ),
              );
            case '/restaurant-analytics':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['restaurant'],
                  child: RestaurantAnalyticsScreen(),
                ),
              );
            case '/restaurant-settings':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['restaurant'],
                  child: RestaurantSettingsScreen(),
                ),
              );
            case '/menu-management':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['restaurant'],
                  child: MenuManagementScreen(),
                ),
              );
            case '/grocery-management':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['restaurant'],
                  child: GroceryManagementScreen(),
                ),
              );
            case '/restaurant-detail':
              if (settings.arguments is! Restaurant) return null;
              final restaurant = settings.arguments as Restaurant;
              return MaterialPageRoute(
                builder: (context) => RoleGuard(
                  allowedRoles: const ['user'],
                  child: RestaurantDetailScreen(restaurant: restaurant),
                ),
              );
            case '/cart':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: CartScreen(),
                ),
              );
            case '/grocery-cart':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: GroceryCartScreen(),
                ),
              );
            case '/checkout':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: CheckoutScreen(),
                ),
              );
            case '/grocery-checkout':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: GroceryCheckoutScreen(),
                ),
              );
            case '/order-tracking':
              final orderId = settings.arguments as String?;
              return MaterialPageRoute(
                builder: (context) => RoleGuard(
                  allowedRoles: const ['user'],
                  child: OrderTrackingScreen(orderId: orderId),
                ),
              );
            case '/customer-profile':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: CustomerProfileScreen(),
                ),
              );
            case '/review':
              if (settings.arguments is! Order) return null;
              final order = settings.arguments as Order;
              return MaterialPageRoute(
                builder: (context) => RoleGuard(
                  allowedRoles: const ['user'],
                  child: ReviewScreen(order: order),
                ),
              );
            case '/notifications':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: NotificationsScreen(),
                ),
              );
            case '/loyalty':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: LoyaltyScreen(),
                ),
              );
            case '/address-book':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: AddressBookScreen(),
                ),
              );
            case '/order-history':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: OrderHistoryScreen(),
                ),
              );
            case '/driver-earnings':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: DriverEarningsScreen(),
                ),
              );
            case '/driver-wallet':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: DriverWalletScreen(),
                ),
              );
            case '/driver-earnings-advanced':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: AdvancedEarningsScreen(),
                ),
              );
            case '/driver-performance':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: DriverPerformanceScreen(),
                ),
              );
            case '/driver-heatmap':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: DemandHeatmapScreen(),
                ),
              );
            case '/admin-promos':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminPromosScreen(),
                ),
              );
            case '/admin-chats':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminChatsScreen(),
                ),
              );
            case '/admin-payouts':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminPayoutsScreen(),
                ),
              );
            case '/admin-financials':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminFinancialsScreen(),
                ),
              );
            case '/admin-analytics':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminAnalyticsScreen(),
                ),
              );
            case '/admin-ai-panel':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminAiPanelScreen(),
                ),
              );
            case '/admin-earnings':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminEarningsScreen(),
                ),
              );
            case '/admin-orders':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminOrdersScreen(),
                ),
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
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: ReferralScreen(),
                ),
              );
            case '/driver-referral':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: DriverReferralScreen(),
                ),
              );
            case '/restaurant-referral':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['restaurant'],
                  child: RestaurantReferralScreen(),
                ),
              );
            case '/earnings':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: EarningsScreen(),
                ),
              );
            case '/favorites':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: FavoritesScreen(),
                ),
              );
            case '/search':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: SmartSearchScreen(),
                ),
              );
            case '/driver-leaderboard':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['driver'],
                  child: DriverLeaderboardScreen(),
                ),
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
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: RefundDisputeScreen(),
                ),
              );
            case '/group-orders':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: GroupOrderScreen(),
                ),
              );
            case '/group-order-detail':
              final groupOrderId = settings.arguments as String?;
              if (groupOrderId == null) return null;
              return MaterialPageRoute(
                builder: (context) => RoleGuard(
                  allowedRoles: const ['user'],
                  child: GroupOrderDetailScreen(groupOrderId: groupOrderId),
                ),
              );
            case '/subscriptions':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: SubscriptionScreen(),
                ),
              );
            case '/feedback':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: FeedbackScreen(),
                ),
              );
            case '/admin-disputes':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminDisputesScreen(),
                ),
              );
            case '/admin-feedback':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminFeedbackScreen(),
                ),
              );
            case '/admin-surge':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminSurgeScreen(),
                ),
              );
            case '/admin-banners':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminBannersScreen(),
                ),
              );
            case '/admin-lookup':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminLookupScreen(),
                ),
              );
            case '/admin-contract':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminContractScreen(),
                ),
              );
            case '/admin-regions':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminRegionsScreen(),
                ),
              );
            case '/admin-ads':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminAdsScreen(),
                ),
              );
            case '/admin-pricing':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminPricingScreen(),
                ),
              );
            case '/wallet':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['user'],
                  child: WalletScreen(),
                ),
              );
            case '/restaurant-loyalty':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['restaurant'],
                  child: RestaurantLoyaltyScreen(),
                ),
              );
            case '/restaurant-offer':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['restaurant'],
                  child: RestaurantOfferScreen(),
                ),
              );
            case '/restaurant-contract':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['restaurant'],
                  child: RestaurantContractScreen(),
                ),
              );
            case '/admin-loyalty':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminLoyaltyScreen(),
                ),
              );
            case '/admin-mealhub':
              return MaterialPageRoute(
                builder: (context) => const RoleGuard(
                  allowedRoles: ['admin'],
                  child: AdminMealhubScreen(),
                ),
              );
            case '/settings':
              return MaterialPageRoute(
                builder: (context) => const AppSettingsScreen(),
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
