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
  final String? mealPlanId;
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

  // Uber One-style fields
  final String? planType; // 'basic' | 'pro'
  final String? stripeSubscriptionId;
  final String? stripeCustomerId;
  final DateTime? currentPeriodEnd;
  final int deliveriesRemaining;
  final int deliveriesUsed;
  final double serviceFeeDiscount;

  UserSubscription({
    required this.id,
    required this.userId,
    this.mealPlanId,
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
    this.planType,
    this.stripeSubscriptionId,
    this.stripeCustomerId,
    this.currentPeriodEnd,
    this.deliveriesRemaining = 0,
    this.deliveriesUsed = 0,
    this.serviceFeeDiscount = 0.0,
  });

  factory UserSubscription.fromJson(Map<String, dynamic> json) {
    return UserSubscription(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      mealPlanId: json['meal_plan_id'] as String?,
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
      planType: json['plan_type'] as String?,
      stripeSubscriptionId: json['stripe_subscription_id'] as String?,
      stripeCustomerId: json['stripe_customer_id'] as String?,
      currentPeriodEnd: json['current_period_end'] != null
          ? DateTime.parse(json['current_period_end'] as String)
          : null,
      deliveriesRemaining: json['deliveries_remaining'] as int? ?? 0,
      deliveriesUsed: json['deliveries_used'] as int? ?? 0,
      serviceFeeDiscount:
          (json['service_fee_discount'] as num?)?.toDouble() ?? 0.0,
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
    'plan_type': planType,
    'stripe_subscription_id': stripeSubscriptionId,
    'deliveries_remaining': deliveriesRemaining,
    'deliveries_used': deliveriesUsed,
    'service_fee_discount': serviceFeeDiscount,
  };

  bool get isActive => status == 'active';
  bool get isPaused => status == 'paused';
  bool get hasDeliveries => deliveriesRemaining > 0;

  String get planLabel {
    switch (planType) {
      case 'basic':
        return 'MealHub Basic';
      case 'pro':
        return 'MealHub Pro';
      default:
        return mealPlan?.name ?? 'Subscription';
    }
  }
}
