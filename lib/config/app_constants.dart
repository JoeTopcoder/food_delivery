class AppConstants {
  // App Info
  static const String appName = 'FoodDriver';
  static const String appVersion = '1.0.0';

  // Supabase Configuration
  static const String supabaseUrl = 'https://yharweliruemjexmuuxn.supabase.co';
  static const String supabaseAnonKey =
      'sb_publishable_e-McqdkcLyoxV89A86lWGw_hD3vyVP6';

  // NCB Payment Gateway Configuration (TEST MODE)
  // TODO: Replace test keys and endpoints with real NCB API details
  static const String ncbApiKey = String.fromEnvironment(
    'NCB_API_KEY',
    defaultValue: 'test_ncb_api_key',
  );
  static const String ncbApiUrl = String.fromEnvironment(
    'NCB_API_URL',
    defaultValue: 'https://sandbox.ncb.com/api/payments',
  );
  static const String ncbPayoutUrl = String.fromEnvironment(
    'NCB_PAYOUT_URL',
    defaultValue: 'https://sandbox.ncb.com/api/payouts',
  );
  static const String ncbCallbackUrl =
      '$supabaseUrl/functions/v1/ncb-payment-callback';
  static const String ncbBanksFunction = '/ncb-banks';
  static const String ncbInitiatePaymentFunction = '/ncb-initiate-payment';
  static const String ncbProcessPayoutFunction = '/ncb-process-payout';
  static const String ncbPaymentCallbackFunction = '/ncb-payment-callback';

  // WiPay configuration fully removed after migration

  static const String appBaseUrl = 'https://applizonecentralja.com';

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

  // Agora Voice Call
  static const String agoraAppId = '821e6ba951734d04910ff6c6d5b5fba5';

  // Timeouts (in seconds) — overridden from DB at startup
  static int apiTimeout = 30;
  static int connectionTimeout = 10;

  // Pagination
  static int pageSize = 20;

  // Currency
  static const String currencySymbol = 'JMD\$';

  // ── Business Constants (defaults — overridden from app_config table) ──────

  // Fees
  static double taxRate = 0.10;
  static double defaultDeliveryFee = 50.0;
  static double driverFeePerDelivery = 50.0;
  static double cardFeePercent = 2.5;
  static double bankTransferFeePercent = 1.0;
  static double cashFeePercent = 0;

  // Delivery (distance-based)
  static double deliveryBaseFee = 50.0;
  static double deliveryPerKmFee = 30.0;
  static double deliveryBaseKm = 3.0;
  static double deliveryMaxKm = 25.0;
  static double deliverySurgeMultiplier = 1.0;

  // Loyalty
  static double loyaltyPointValue = 0.10;
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

  // Tips
  static List<double> presetTips = [50, 100, 200, 500];

  // System
  static int orderAssignmentCutoffMinutes = 30;
}
