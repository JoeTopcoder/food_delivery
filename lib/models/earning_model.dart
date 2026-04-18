/// Earning tier levels
enum EarningTier { customer, builder, leader }

/// Earning account — tracks a user's referral earning tier & stats
class EarningAccount {
  final String id;
  final String userId;
  final String? userName;
  final String tier; // 'customer', 'builder', 'leader'
  final double totalEarned;
  final int totalDirectRefs;
  final int totalIndirectRefs;
  final int totalOrdersGenerated;
  final double monthlyEarned;
  final int monthlyOrders;
  final String monthKey;
  final DateTime createdAt;
  final DateTime updatedAt;

  const EarningAccount({
    required this.id,
    required this.userId,
    this.userName,
    this.tier = 'customer',
    this.totalEarned = 0,
    this.totalDirectRefs = 0,
    this.totalIndirectRefs = 0,
    this.totalOrdersGenerated = 0,
    this.monthlyEarned = 0,
    this.monthlyOrders = 0,
    this.monthKey = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory EarningAccount.fromJson(Map<String, dynamic> json) {
    // userName may come from a joined users row
    final usersData = json['users'];
    final userName = usersData is Map ? usersData['name'] as String? : null;
    return EarningAccount(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      userName: userName,
      tier: json['tier'] as String? ?? 'customer',
      totalEarned: (json['total_earned'] as num? ?? 0).toDouble(),
      totalDirectRefs: (json['total_direct_refs'] as num? ?? 0).toInt(),
      totalIndirectRefs: (json['total_indirect_refs'] as num? ?? 0).toInt(),
      totalOrdersGenerated: (json['total_orders_generated'] as num? ?? 0)
          .toInt(),
      monthlyEarned: (json['monthly_earned'] as num? ?? 0).toDouble(),
      monthlyOrders: (json['monthly_orders'] as num? ?? 0).toInt(),
      monthKey: json['month_key'] as String? ?? '',
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  EarningTier get tierEnum {
    switch (tier) {
      case 'leader':
        return EarningTier.leader;
      case 'builder':
        return EarningTier.builder;
      default:
        return EarningTier.customer;
    }
  }

  String get tierDisplayName {
    switch (tier) {
      case 'leader':
        return 'Leader';
      case 'builder':
        return 'Builder';
      default:
        return 'Customer';
    }
  }

  /// How many more refs to reach next tier
  int get refsToNextTier {
    switch (tier) {
      case 'customer':
        return (EarningConfig.builderMinRefs - totalDirectRefs).clamp(0, 999);
      case 'builder':
        return (EarningConfig.leaderMinRefs - totalDirectRefs).clamp(0, 999);
      default:
        return 0;
    }
  }

  String get nextTierName {
    switch (tier) {
      case 'customer':
        return 'Builder';
      case 'builder':
        return 'Leader';
      default:
        return 'Max';
    }
  }

  double get monthlyCapRemaining => (EarningConfig.monthlyCap - monthlyEarned)
      .clamp(0, EarningConfig.monthlyCap);
}

/// Individual earning transaction
class EarningTransaction {
  final String id;
  final String userId;
  final String type;
  final double amount;
  final String? sourceUserId;
  final String? orderId;
  final String description;
  final DateTime? expiresAt;
  final bool isExpired;
  final DateTime createdAt;

  const EarningTransaction({
    required this.id,
    required this.userId,
    required this.type,
    required this.amount,
    this.sourceUserId,
    this.orderId,
    this.description = '',
    this.expiresAt,
    this.isExpired = false,
    required this.createdAt,
  });

  factory EarningTransaction.fromJson(Map<String, dynamic> json) =>
      EarningTransaction(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        type: json['type'] as String,
        amount: (json['amount'] as num).toDouble(),
        sourceUserId: json['source_user_id'] as String?,
        orderId: json['order_id'] as String?,
        description: json['description'] as String? ?? '',
        expiresAt: json['expires_at'] != null
            ? DateTime.parse(json['expires_at'] as String)
            : null,
        isExpired: json['is_expired'] as bool? ?? false,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  String get typeLabel {
    switch (type) {
      case 'signup_bonus':
        return 'Signup Bonus';
      case 'referred_first_order':
        return 'Welcome Bonus';
      case 'direct_order':
        return 'Direct Referral';
      case 'indirect_order':
        return 'Network Bonus';
      case 'volume_bonus':
        return 'Volume Bonus';
      case 'restaurant_referral':
        return 'Restaurant Referral';
      case 'expired':
        return 'Expired';
      case 'adjustment':
        return 'Adjustment';
      default:
        return type;
    }
  }

  bool get isCredit => amount > 0;
}

/// Config defaults for earning system — overridden from app_config at startup
class EarningConfig {
  static double referrerSignupBonus = 2.00;
  static double referredFirstOrderBonus = 3.00;
  static double directOrderRate = 0.30;
  static double indirectOrderRate = 0.10;
  static int builderMinRefs = 5;
  static int builderMinOrders = 50;
  static int leaderMinRefs = 15;
  static int leaderMinOrders = 150;
  static double volumeBonus300 = 25.00;
  static double volumeBonus1000 = 100.00;
  static double volumeBonus3000 = 250.00;
  static double monthlyCap = 300.00;
  static int creditExpiryDays = 21;
  static double minOrderToUse = 10.00;
  static double maxCreditPct = 0.50;
  static double restaurantRefCredits = 50.00;
  static double restaurantRefCommissionDiscount = 0.02;
}
