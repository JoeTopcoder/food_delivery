/// Represents a tracked user behavior event.
class UserEvent {
  final String id;
  final String userId;
  final String eventType;
  final Map<String, dynamic> metadata;
  final String? sessionId;
  final DateTime createdAt;

  const UserEvent({
    required this.id,
    required this.userId,
    required this.eventType,
    this.metadata = const {},
    this.sessionId,
    required this.createdAt,
  });

  factory UserEvent.fromJson(Map<String, dynamic> json) => UserEvent(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    eventType: json['event_type'] as String,
    metadata: (json['metadata'] as Map<String, dynamic>?) ?? {},
    sessionId: json['session_id'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'event_type': eventType,
    'metadata': metadata,
    if (sessionId != null) 'session_id': sessionId,
  };
}

/// Standard event type constants.
abstract class EventTypes {
  static const appOpen = 'app_open';
  static const restaurantView = 'restaurant_view';
  static const menuItemView = 'menu_item_view';
  static const addToCart = 'add_to_cart';
  static const removeFromCart = 'remove_from_cart';
  static const orderCompleted = 'order_completed';
  static const searchQuery = 'search_query';
  static const categoryTap = 'category_tap';
  static const dealClicked = 'deal_clicked';
  static const couponApplied = 'coupon_applied';
  static const promoViewed = 'promo_viewed';
  static const favoriteToggle = 'favorite_toggle';
  static const scrollStop = 'scroll_stop';
  static const bannerTap = 'banner_tap';
}
