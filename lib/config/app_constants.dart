class AppConstants {
  // App Info
  static const String appName = '7DASH';
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

  // Stripe Payment Configuration — Stripe is the ONLY payment method
  static String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PK',
    defaultValue:
        'pk_test_51TMsI4IxFR3jJr2a8pgcDa3D4XSC59nBD3aeEna8bxDGOGFaIQ342E7v4g8u8DwdA0vWn88g8n7DcMkJFaYGyxtD00s1C92qCF',
  );
  static const String stripeRestrictedKey = String.fromEnvironment(
    'STRIPE_RK',
    defaultValue:
        'rk_test_51TMsI4IxFR3jJr2almj9Qkbmc9jxdJJ52wnMHe3zAYeoVal9QqCR2yPtfCSenJgPUeFK3zWFU9qSHr7IV1nfVjY100GKkOtn7q',
  );
  static const String stripePaymentFunction = 'stripe-payment';
  static const String stripeMerchantId = 'merchant.com.sevendash.app';

  // Stripe-only: Legacy Lunipay and WiPay configurations removed

  // Stripe-only: Legacy NCB, WiPay, and Lunipay configurations removed

  static const String appBaseUrl = 'https://mealhubcayman.com';
  static const String privacyPolicyUrl = '$appBaseUrl/privacy-policy';
  static const String termsOfServiceUrl = '$appBaseUrl/terms-of-service';

  static String get supabaseFunctionsBaseUrl => '$supabaseUrl/functions/v1';
  static String get ncbCallbackUrlFull =>
      '$supabaseUrl/functions/v1/ncb-payment-callback';

  // User Roles
  static const String roleCustomer = 'customer';
  static const String roleUser = 'user';
  static const String roleRestaurant = 'restaurant';
  static const String roleDriver = 'driver';
  static const String roleAdmin = 'admin';
  static const String roleServiceProvider = 'service_provider';

  // Order Status
  static const String orderPending = 'pending';
  static const String orderConfirmed = 'confirmed';
  static const String orderPreparing = 'preparing';
  static const String orderReady = 'ready';
  static const String orderPickedUp = 'picked_up';
  static const String orderOnTheWay = 'on_the_way';
  static const String orderDelivered = 'delivered';
  static const String orderCancelled = 'cancelled';
  static const String orderPartiallyCancelled = 'partially_cancelled';

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
  // Multi-restaurant order tables
  static const String tableMasterOrders = 'master_orders';
  static const String tableRestaurantOrders = 'restaurant_orders';
  static const String tableRestaurantOrderItems = 'restaurant_order_items';

  // Laundry Module Tables
  static const String tableLaundryProviders       = 'laundry_providers';
  static const String tableLaundryServices        = 'laundry_services';
  static const String tableLaundryProviderServices = 'laundry_provider_services';
  static const String tableLaundryPricing         = 'laundry_pricing';
  static const String tableLaundryBookings        = 'laundry_bookings';
  static const String tableLaundryBookingItems    = 'laundry_booking_items';
  static const String tableLaundryStatusHistory   = 'laundry_status_history';
  static const String tableLaundryPhotos          = 'laundry_photos';
  static const String tableLaundryWeights         = 'laundry_weights';
  static const String tableLaundryDriverAssignments = 'laundry_driver_assignments';
  static const String tableLaundryReviews         = 'laundry_reviews';
  static const String tableLaundryDisputes        = 'laundry_disputes';

  // Laundry Role
  static const String roleLaundryProvider = 'laundry_provider';

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

  // Currency — overridden from app_config table at startup
  static String currencySymbol = '\$';
  static String currencyCode = 'USD';
  static String currencyName = 'US Dollar';
  static const String countryName = 'Cayman Islands';

  // ── Business Constants (defaults — overridden from app_config table) ──────

  // Fees
  static double taxRate = 0.0;
  static bool taxEnabled = false;
  static double platformServiceFeeRate = 0.05;
  static double platformCommissionCap = 0.85;
  static double defaultDeliveryFee = 5.0;
  static double pickupServiceFee = 2.0;
  static double driverFeePerDelivery = 5.0;
  static double cardFeePercent = 0;
  static double cashFeePercent = 0;
  static double bankTransferFeePercent = 0;
  static double cardVerificationChargeMin = 0;
  static double cardVerificationChargeMax = 3;

  // Ride promotional banners
  static bool ridePromoFirstRideEnabled = true;
  static String ridePromoFirstRideTitle = 'First ride free!';
  static String ridePromoFirstRideSubtitle = 'Use code FIRSTRIDE at checkout';
  static String ridePromoFirstRideCode = 'FIRSTRIDE';
  static String ridePromoFirstRideCta = 'Book now';
  static String ridePromoReturningTitle = 'Ready for your next ride?';
  static String ridePromoReturningSubtitle =
      'Fast, reliable rides at your fingertips';
  static String ridePromoReturningCta = 'Book a ride';

  // Delivery (distance-based, USD — $2.00–$2.50 per mile)
  static double deliveryBaseFee = 3.0; // base fee for first baseMiles
  static double deliveryPerMileFee = 2.00; // $/mile standard
  static double deliveryPerMileFeePeak = 2.50; // $/mile peak/surge cap
  static double deliveryPerKmFee = 3.22; // $2.00/mi in km (fallback)
  static double deliveryBaseMiles = 1.0; // miles included in base fee
  static double deliveryBaseKm = 1.6; // ~1 mile in km (fallback)
  static double deliveryMaxKm = 30.0;
  static double deliverySurgeMultiplier = 1.0;
  static double driverPayPercent = 0.80;
  static double minDeliveryFee = 3.0;
  static double driverBonusPerOrder = 0.0;

  // Driver pay ($1.50/mile compliance)
  static double driverRatePerMile = 1.50;
  static double driverRatePerKm = 0.93; // $1.50/mi ÷ 1.609
  static double driverRatePerMinute = 0.15;
  static double driverWaitPayPerMinute = 0.20;
  static double driverMinBasePay = 3.0;
  static double driverEarningsFloor = 20.0;
  static double driverBoostAmount = 0.0;
  static const double kmToMiles = 0.621371;

  // Driver order stacking
  static int driverMaxStackOrders = 3;
  static double driverStackDistanceKm = 2.0;
  static int driverStackMaxDelay = 10;
  static double driverStackMinIncrease = 0.30;

  // Driver tiers (score thresholds 0–100)
  static int driverTierSilverScore = 60;
  static int driverTierGoldScore = 75;
  static int driverTierEliteScore = 90;

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
  static double restaurantCommissionPct = 0.15;

  // Car Services
  static double carServiceMobileFee = 15.00;
  static double carServicePlatformFeePct = 0.20;
  static double carServiceServiceFee = 2.50;

  // Tips (in USD)
  static List<double> presetTips = [2, 5, 10, 20];

  // Subscription (MealHub+) — overridden from app_config table
  static double subscriptionBasicPrice = 12.0;
  static int subscriptionBasicDeliveries = 9;
  static double subscriptionProPrice = 24.0;
  static int subscriptionProDeliveries = 22;
  static double subscriptionMinCart = 15.0;
  static double subscriptionServiceFeeDiscount = 0.50;

  // Ride sharing — overridden from app_config table at startup
  static double airportSurchargeJmd = 1500.0;
  static int rideBookingAdvanceDays = 30;
  static int scheduledRideBufferHours = 1;
  static int rideDriverOfferTimeoutSecs = 90;
  static double rideMaxSearchRadiusKm = 30.0;
  static int rideDriverSchedAdvanceHours = 72;

  // Support contact — overridden from app_config table at startup
  static String supportPhone = '';
  static String supportEmail = '';
  static String supportWhatsApp = '';

  // System
  static int orderAssignmentCutoffMinutes = 30;
  static bool maintenanceMode = false;

  /// Canonical food categories surfaced on the customer home screen.
  /// Restaurants should tag their menu items with one of these names so they
  /// appear when a customer taps the matching category chip.
  static const List<Map<String, String>> homeFoodCategories = [
    {'emoji': '🍳', 'name': 'Breakfast'},
    {'emoji': '🍔', 'name': 'Fast Food'},
    {'emoji': '🍕', 'name': 'Pizza'},
    {'emoji': '🍗', 'name': 'Chicken'},
    {'emoji': '🌮', 'name': 'Mexican'},
    {'emoji': '🍜', 'name': 'Chinese'},
    {'emoji': '🍣', 'name': 'Sushi'},
    {'emoji': '🥗', 'name': 'Healthy'},
    {'emoji': '🍰', 'name': 'Dessert'},
    {'emoji': '☕', 'name': 'Coffee'},
    {'emoji': '🧋', 'name': 'Drinks'},
    {'emoji': '🌱', 'name': 'Vegan'},
  ];

  /// Just the names from [homeFoodCategories].
  static List<String> get homeFoodCategoryNames =>
      homeFoodCategories.map((c) => c['name']!).toList();
}
