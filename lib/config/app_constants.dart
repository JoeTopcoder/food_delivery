class AppConstants {
  // App Info
  static const String appName = 'MealHub';
  static const String appVersion = '1.0.0';

  // Supabase Configuration (override via --dart-define at build time)
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://yharweliruemjexmuuxn.supabase.co',
  );
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'sb_publishable_e-McqdkcLyoxV89A86lWGw_hD3vyVP6',
  );

  // Stripe Payment Configuration — loaded from app_config DB at startup
  static String stripePublishableKey =
      'pk_test_51TMsI4IxFR3jJr2a8pgcDa3D4XSC59nBD3aeEna8bxDGOGFaIQ342E7v4g8u8DwdA0vWn88g8n7DcMkJFaYGyxtD00s1C92qCF';
  static const String stripePaymentFunction = 'stripe-payment';
  static const String stripeMerchantId = 'merchant.com.foodhub.delivery';

  // Legacy NCB configuration (kept for reference, no longer used in app)
  static const String ncbApiKey = String.fromEnvironment(
    'NCB_API_KEY',
    defaultValue: 'test_ncb_api_key',
  );
  static const String ncbCallbackUrl =
      '$supabaseUrl/functions/v1/ncb-payment-callback';
  static const String ncbInitiatePaymentFunction = '/ncb-initiate-payment';
  static const String ncbPaymentCallbackFunction = '/ncb-payment-callback';

  static const String appBaseUrl = 'https://mealhubcayman.com';
  static const String privacyPolicyUrl = '$appBaseUrl/privacy-policy';
  static const String termsOfServiceUrl = '$appBaseUrl/terms-of-service';

  static String get supabaseFunctionsBaseUrl => '$supabaseUrl/functions/v1';
  static String get ncbCallbackUrlFull =>
      '$supabaseUrl/functions/v1/ncb-payment-callback';

  // User Roles
  static const String roleUser = 'user';
  static const String roleRestaurant = 'restaurant';
  static const String roleDriver = 'driver';
  static const String roleAdmin = 'admin';

  // Order Status
  static const String orderPending = 'pending';
  static const String orderConfirmed = 'confirmed';
  static const String orderPreparing = 'preparing';
  static const String orderReady = 'ready';
  static const String orderPickedUp = 'picked_up';
  static const String orderOnTheWay = 'on_the_way';
  static const String orderDelivered = 'delivered';
  static const String orderCancelled = 'cancelled';

  // Payment Status
  static const String paymentPending = 'pending';
  static const String paymentCompleted = 'completed';
  static const String paymentFailed = 'failed';

  // Database Tables
  static const String tableUsers = 'users';
  static const String tableRestaurants = 'restaurants';
  static const String tableMenus = 'menus';
  static const String tableOrders = 'orders';
  static const String tableOrderItems = 'order_items';
  static const String tableDrivers = 'drivers';
  static const String tablePayments = 'payments';
  static const String tableReviews = 'reviews';
  static const String tableNotifications = 'notifications';
  static const String tableMenuItemSides = 'menu_item_sides';
  static const String tableOrderItemSides = 'order_item_sides';
  static const String tableMenuOptionGroups = 'menu_option_groups';
  static const String tableMenuOptionChoices = 'menu_option_choices';
  static const String tableUserEvents = 'user_events';
  static const String tableUserIntelligenceProfiles =
      'user_intelligence_profiles';
  static const String tableAiRecommendations = 'ai_recommendations';
  static const String tableUserCoupons = 'user_coupons';
  static const String tableRestaurantEmbeddings = 'restaurant_embeddings';

  // Notification Types
  static const String notificationTypeNewOrder = 'new_order';
  static const String notificationTypeOrderStatus = 'order_status_update';
  static const String notificationTypeDeliveryUpdate = 'delivery_update';
  static const String notificationTypePaymentStatus = 'payment_status';

  // FCM Topics
  static String getFCMTopicRestaurant(String restaurantId) =>
      'restaurant_$restaurantId';
  static String getFCMTopicDriver(String driverId) => 'driver_$driverId';
  static String getFCMTopicCustomer(String customerId) =>
      'customer_$customerId';
  static const String fcmTopicAdmins = 'admins';
  static const String fcmTopicAvailableDrivers = 'available_drivers';
  static const String fcmTopicAllRestaurants = 'all_restaurants';

  // Agora Voice Call (override via --dart-define for production)
  static const String agoraAppId = String.fromEnvironment(
    'AGORA_APP_ID',
    defaultValue: '821e6ba951734d04910ff6c6d5b5fba5',
  );

  // Timeouts (in seconds) — overridden from DB at startup
  static int apiTimeout = 30;
  static int connectionTimeout = 10;

  // Pagination
  static int pageSize = 20;

  // Currency (US Dollar)
  static const String currencySymbol = '\$';
  static const String currencyCode = 'USD';
  static const String countryName = 'Cayman Islands';

  // ── Business Constants (defaults — overridden from app_config table) ──────

  // Fees (in USD)
  static double taxRate = 0.0; // No income tax in Cayman Islands
  static double defaultDeliveryFee = 5.0;
  static double pickupServiceFee = 2.0;
  static double driverFeePerDelivery = 5.0;
  static double cardFeePercent = 2.5;
  static double bankTransferFeePercent = 1.0;
  static double cashFeePercent = 0;

  // Delivery (distance-based, USD)
  static double deliveryBaseFee = 5.0;
  static double deliveryPerKmFee = 1.50;
  static double deliveryBaseKm = 3.0;
  static double deliveryMaxKm = 30.0;
  static double deliverySurgeMultiplier = 1.0;
  static double driverPayPercent = 0.80;
  static double minDeliveryFee = 3.0;
  static double driverBonusPerOrder = 0.0;

  // Peak hour pricing
  static double peakAddonFee = 1.0;
  static int peakHoursStart = 11;
  static int peakHoursEnd = 14;
  static int peakHoursStart2 = 18;
  static int peakHoursEnd2 = 21;

  /// Returns true if the current local hour falls within a peak window.
  static bool get isPeakHour {
    final h = DateTime.now().hour;
    return (h >= peakHoursStart && h < peakHoursEnd) ||
        (h >= peakHoursStart2 && h < peakHoursEnd2);
  }

  // Loyalty
  static double loyaltyPointValue = 0.01;
  static double loyaltyMaxRedemptionPercent = 0.20;
  static int loyaltyPointsPer100 = 10;
  static int loyaltyTierSilverThreshold = 500;
  static int loyaltyTierGoldThreshold = 2000;
  static int loyaltyTierPlatinumThreshold = 5000;
  static double loyaltyMultiplierBronze = 1.0;
  static double loyaltyMultiplierSilver = 1.25;
  static double loyaltyMultiplierGold = 1.5;
  static double loyaltyMultiplierPlatinum = 2.0;

  // Commission
  static double defaultCommissionRate = 0.15;

  // Tips (in USD)
  static List<double> presetTips = [2, 5, 10, 20];

  // Subscription (MealHub+) — overridden from app_config table
  static double subscriptionBasicPrice = 12.0;
  static int subscriptionBasicDeliveries = 9;
  static double subscriptionProPrice = 24.0;
  static int subscriptionProDeliveries = 22;
  static double subscriptionMinCart = 15.0;
  static double subscriptionServiceFeeDiscount = 0.50;

  // System
  static int orderAssignmentCutoffMinutes = 30;
}
