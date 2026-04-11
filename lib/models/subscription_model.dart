class MealPlan {
  final String id;
  final String name;
  final String? description;
  final String? restaurantId;
  final double price;
  final String frequency;
  final int mealsPerPeriod;
  final List<dynamic> items;
  final bool isActive;
  final DateTime createdAt;

  MealPlan({
    required this.id,
    required this.name,
    this.description,
    this.restaurantId,
    required this.price,
    required this.frequency,
    this.mealsPerPeriod = 1,
    this.items = const [],
    this.isActive = true,
    required this.createdAt,
  });

  factory MealPlan.fromJson(Map<String, dynamic> json) {
    return MealPlan(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      restaurantId: json['restaurant_id'] as String?,
      price: (json['price'] as num).toDouble(),
      frequency: json['frequency'] as String,
      mealsPerPeriod: json['meals_per_period'] as int? ?? 1,
      items: json['items'] as List<dynamic>? ?? [],
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'restaurant_id': restaurantId,
    'price': price,
    'frequency': frequency,
    'meals_per_period': mealsPerPeriod,
    'items': items,
    'is_active': isActive,
  };

  String get frequencyLabel {
    switch (frequency) {
      case 'daily':
        return 'Daily';
      case 'weekly':
        return 'Weekly';
      case 'monthly':
        return 'Monthly';
      default:
        return frequency;
    }
  }
}

class UserSubscription {
  final String id;
  final String userId;
  final String mealPlanId;
  final String status;
  final DateTime startDate;
  final DateTime? nextDelivery;
  final String? deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final int mealsRemaining;
  final bool autoRenew;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final MealPlan? mealPlan;

  UserSubscription({
    required this.id,
    required this.userId,
    required this.mealPlanId,
    this.status = 'active',
    required this.startDate,
    this.nextDelivery,
    this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.mealsRemaining = 0,
    this.autoRenew = true,
    required this.createdAt,
    this.updatedAt,
    this.mealPlan,
  });

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    return UserSubscription(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      mealPlanId: json['meal_plan_id'] as String,
      status: json['status'] as String? ?? 'active',
      startDate: DateTime.parse(json['start_date'] as String),
      nextDelivery: json['next_delivery'] != null
          ? DateTime.parse(json['next_delivery'] as String)
          : null,
      deliveryAddress: json['delivery_address'] as String?,
      deliveryLatitude: (json['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (json['delivery_longitude'] as num?)?.toDouble(),
      mealsRemaining: json['meals_remaining'] as int? ?? 0,
      autoRenew: json['auto_renew'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      mealPlan: json['meal_plans'] != null
          ? MealPlan.fromJson(json['meal_plans'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'meal_plan_id': mealPlanId,
    'status': status,
    'start_date': startDate.toIso8601String().split('T')[0],
    'next_delivery': nextDelivery?.toIso8601String().split('T')[0],
    'delivery_address': deliveryAddress,
    'delivery_latitude': deliveryLatitude,
    'delivery_longitude': deliveryLongitude,
    'meals_remaining': mealsRemaining,
    'auto_renew': autoRenew,
  };

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
}
