import '../config/app_constants.dart';

class LoyaltyAccount {
  final String id;
  final String userId;
  final int points;
  final int totalEarned;
  final int totalRedeemed;
  final String tier; // bronze, silver, gold, platinum
  final DateTime updatedAt;

  const LoyaltyAccount({
    required this.id,
    required this.userId,
    required this.points,
    required this.totalEarned,
    required this.totalRedeemed,
    this.tier = 'bronze',
    required this.updatedAt,
  });

  factory LoyaltyAccount.fromJson(Map<String, dynamic> json) => LoyaltyAccount(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    points: (json['points'] as num? ?? 0).toInt(),
    totalEarned: (json['total_earned'] as num? ?? 0).toInt(),
    totalRedeemed: (json['total_redeemed'] as num? ?? 0).toInt(),
    tier: json['tier'] as String? ?? 'bronze',
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  /// Points are worth the DB-configured amount each
  double get redemptionValue => points * AppConstants.loyaltyPointValue;

  /// Max redeemable against a given order total (DB-driven cap)
  double maxRedeemable(double orderTotal) {
    final cap = orderTotal * AppConstants.loyaltyMaxRedemptionPercent;
    return redemptionValue < cap ? redemptionValue : cap;
  }

  /// Tier multiplier for points earning (DB-driven)
  double get tierMultiplier {
    switch (tier) {
      case 'platinum':
        return AppConstants.loyaltyMultiplierPlatinum;
      case 'gold':
        return AppConstants.loyaltyMultiplierGold;
      case 'silver':
        return AppConstants.loyaltyMultiplierSilver;
      default:
        return AppConstants.loyaltyMultiplierBronze;
    }
  }

  /// Points needed for next tier (DB-driven thresholds)
  int get pointsToNextTier {
    switch (tier) {
      case 'bronze':
        return AppConstants.loyaltyTierSilverThreshold - totalEarned;
      case 'silver':
        return AppConstants.loyaltyTierGoldThreshold - totalEarned;
      case 'gold':
        return AppConstants.loyaltyTierPlatinumThreshold - totalEarned;
      default:
        return 0; // Platinum is max
    }
  }

  String get nextTierName {
    switch (tier) {
      case 'bronze':
        return 'Silver';
      case 'silver':
        return 'Gold';
      case 'gold':
        return 'Platinum';
      default:
        return 'Max';
    }
  }
}

class LoyaltyTransaction {
  final String id;
  final String userId;
  final String? orderId;
  final int points;
  final String type; // 'earn' | 'redeem'
  final String description;
  final DateTime createdAt;

  const LoyaltyTransaction({
    required this.id,
    required this.userId,
    this.orderId,
    required this.points,
    required this.type,
    required this.description,
    required this.createdAt,
  });

  factory LoyaltyTransaction.fromJson(Map<String, dynamic> json) =>
      LoyaltyTransaction(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        orderId: json['order_id'] as String?,
        points: (json['points'] as num).toInt(),
        type: json['type'] as String,
        description: json['description'] as String? ?? '',
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
