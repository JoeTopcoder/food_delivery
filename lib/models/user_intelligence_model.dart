/// User Intelligence Profile — the user's "behavioral DNA".
class UserIntelligenceProfile {
  final String userId;
  final Map<String, double> cuisineScores;
  final double priceSensitivity;
  final double dealSensitivity;
  final double avgOrderValue;
  final double orderFrequency;
  final Map<String, int> preferredOrderTimes;
  final List<String> favoriteCategories;
  final double churnRisk;
  final String userSegment;
  final int totalOrders;
  final int daysSinceLastOrder;
  final double activityScore;
  final String? summaryText;
  final DateTime? lastComputedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserIntelligenceProfile({
    required this.userId,
    this.cuisineScores = const {},
    this.priceSensitivity = 0.5,
    this.dealSensitivity = 0.5,
    this.avgOrderValue = 0,
    this.orderFrequency = 0,
    this.preferredOrderTimes = const {},
    this.favoriteCategories = const [],
    this.churnRisk = 0,
    this.userSegment = 'new_user',
    this.totalOrders = 0,
    this.daysSinceLastOrder = 0,
    this.activityScore = 0,
    this.summaryText,
    this.lastComputedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserIntelligenceProfile.fromJson(Map<String, dynamic> json) {
    final cuisineRaw = json['cuisine_scores'];
    final cuisineScores = <String, double>{};
    if (cuisineRaw is Map) {
      for (final e in cuisineRaw.entries) {
        cuisineScores[e.key.toString()] =
            double.tryParse(e.value.toString()) ?? 0;
      }
    }

    final timesRaw = json['preferred_order_times'];
    final times = <String, int>{};
    if (timesRaw is Map) {
      for (final e in timesRaw.entries) {
        times[e.key.toString()] = int.tryParse(e.value.toString()) ?? 0;
      }
    }

    final catsRaw = json['favorite_categories'];
    final cats = <String>[];
    if (catsRaw is List) {
      for (final c in catsRaw) {
        cats.add(c.toString());
      }
    }

    return UserIntelligenceProfile(
      userId: json['user_id'] as String,
      cuisineScores: cuisineScores,
      priceSensitivity: (json['price_sensitivity'] as num?)?.toDouble() ?? 0.5,
      dealSensitivity: (json['deal_sensitivity'] as num?)?.toDouble() ?? 0.5,
      avgOrderValue: (json['avg_order_value'] as num?)?.toDouble() ?? 0,
      orderFrequency: (json['order_frequency'] as num?)?.toDouble() ?? 0,
      preferredOrderTimes: times,
      favoriteCategories: cats,
      churnRisk: (json['churn_risk'] as num?)?.toDouble() ?? 0,
      userSegment: json['user_segment'] as String? ?? 'new_user',
      totalOrders: json['total_orders'] as int? ?? 0,
      daysSinceLastOrder: json['days_since_last_order'] as int? ?? 0,
      activityScore: (json['activity_score'] as num?)?.toDouble() ?? 0,
      summaryText: json['summary_text'] as String?,
      lastComputedAt: json['last_computed_at'] != null
          ? DateTime.parse(json['last_computed_at'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : DateTime.now(),
    );
  }

  /// The user's #1 cuisine preference, or null.
  String? get topCuisine {
    if (cuisineScores.isEmpty) return null;
    final sorted = cuisineScores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.first.key;
  }

  bool get isNewUser => userSegment == 'new_user';
  bool get isInactive => userSegment == 'inactive';
  bool get isPowerUser => userSegment == 'power_user';
  bool get isHighChurnRisk => churnRisk > 0.7;
  bool get lovesDealS => dealSensitivity > 0.6;
  bool get isPriceSensitive => priceSensitivity > 0.6;

  factory UserIntelligenceProfile.empty(String userId) =>
      UserIntelligenceProfile(
        userId: userId,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
}
