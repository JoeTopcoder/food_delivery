class GroupOrder {
  final String id;
  final String hostUserId;
  final String restaurantId;
  final String name;
  final String inviteCode;
  final String status;
  final DateTime? deadline;
  final String? deliveryAddress;
  final double? deliveryLatitude;
  final double? deliveryLongitude;
  final String? orderId;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<GroupOrderParticipant> participants;

  GroupOrder({
    required this.id,
    required this.hostUserId,
    required this.restaurantId,
    required this.name,
    required this.inviteCode,
    this.status = 'collecting',
    this.deadline,
    this.deliveryAddress,
    this.deliveryLatitude,
    this.deliveryLongitude,
    this.orderId,
    required this.createdAt,
    this.updatedAt,
    this.participants = const [],
  });

  factory GroupOrder.fromJson(Map<String, dynamic> json) {
    return GroupOrder(
      id: json['id'] as String,
      hostUserId: json['host_user_id'] as String,
      restaurantId: json['restaurant_id'] as String,
      name: json['name'] as String? ?? 'Group Order',
      inviteCode: json['invite_code'] as String,
      status: json['status'] as String? ?? 'collecting',
      deadline: json['deadline'] != null
          ? DateTime.parse(json['deadline'] as String)
          : null,
      deliveryAddress: json['delivery_address'] as String?,
      deliveryLatitude: (json['delivery_latitude'] as num?)?.toDouble(),
      deliveryLongitude: (json['delivery_longitude'] as num?)?.toDouble(),
      orderId: json['order_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      participants:
          (json['group_order_participants'] as List<dynamic>?)
              ?.map(
                (e) =>
                    GroupOrderParticipant.fromJson(e as Map<String, dynamic>),
              )
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'host_user_id': hostUserId,
    'restaurant_id': restaurantId,
    'name': name,
    'invite_code': inviteCode,
    'status': status,
    'deadline': deadline?.toIso8601String(),
    'delivery_address': deliveryAddress,
    'delivery_latitude': deliveryLatitude,
    'delivery_longitude': deliveryLongitude,
    'order_id': orderId,
  };

  double get totalAmount =>
      participants.fold(0.0, (sum, p) => sum + p.subtotal);
}

class GroupOrderParticipant {
  final String id;
  final String groupOrderId;
  final String userId;
  final List<dynamic> items;
  final double subtotal;
  final bool isPaid;
  final DateTime joinedAt;
  final String? userName;

  GroupOrderParticipant({
    required this.id,
    required this.groupOrderId,
    required this.userId,
    this.items = const [],
    this.subtotal = 0,
    this.isPaid = false,
    required this.joinedAt,
    this.userName,
  });

  factory GroupOrderParticipant.fromJson(Map<String, dynamic> json) {
    return GroupOrderParticipant(
      id: json['id'] as String,
      groupOrderId: json['group_order_id'] as String,
      userId: json['user_id'] as String,
      items: json['items'] as List<dynamic>? ?? [],
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      isPaid: json['is_paid'] as bool? ?? false,
      joinedAt: DateTime.parse(json['joined_at'] as String),
      userName: json['user_name'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'group_order_id': groupOrderId,
    'user_id': userId,
    'items': items,
    'subtotal': subtotal,
    'is_paid': isPaid,
  };
}
