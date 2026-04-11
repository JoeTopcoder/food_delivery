class Refund {
  final String id;
  final String orderId;
  final String userId;
  final double amount;
  final String reason;
  final String status;
  final String? adminNotes;
  final String refundMethod;
  final DateTime? processedAt;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Refund({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.amount,
    required this.reason,
    this.status = 'pending',
    this.adminNotes,
    this.refundMethod = 'original',
    this.processedAt,
    required this.createdAt,
    this.updatedAt,
  });

  factory Refund.fromJson(Map<String, dynamic> json) {
    return Refund(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      userId: json['user_id'] as String,
      amount: (json['amount'] as num).toDouble(),
      reason: json['reason'] as String,
      status: json['status'] as String? ?? 'pending',
      adminNotes: json['admin_notes'] as String?,
      refundMethod: json['refund_method'] as String? ?? 'original',
      processedAt: json['processed_at'] != null
          ? DateTime.parse(json['processed_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'order_id': orderId,
    'user_id': userId,
    'amount': amount,
    'reason': reason,
    'status': status,
    'admin_notes': adminNotes,
    'refund_method': refundMethod,
    'processed_at': processedAt?.toIso8601String(),
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };
}

class Dispute {
  final String id;
  final String orderId;
  final String userId;
  final String type;
  final String description;
  final List<String> photoUrls;
  final String status;
  final String? resolution;
  final String? resolvedBy;
  final String? refundId;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Dispute({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.type,
    required this.description,
    this.photoUrls = const [],
    this.status = 'open',
    this.resolution,
    this.resolvedBy,
    this.refundId,
    required this.createdAt,
    this.updatedAt,
  });

  factory Dispute.fromJson(Map<String, dynamic> json) {
    return Dispute(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      description: json['description'] as String,
      photoUrls:
          (json['photo_urls'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      status: json['status'] as String? ?? 'open',
      resolution: json['resolution'] as String?,
      resolvedBy: json['resolved_by'] as String?,
      refundId: json['refund_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'order_id': orderId,
    'user_id': userId,
    'type': type,
    'description': description,
    'photo_urls': photoUrls,
    'status': status,
    'resolution': resolution,
    'resolved_by': resolvedBy,
    'refund_id': refundId,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };

  static const disputeTypes = [
    'missing_item',
    'wrong_item',
    'quality',
    'late_delivery',
    'never_delivered',
    'overcharged',
    'other',
  ];

  String get typeLabel {
    switch (type) {
      case 'missing_item':
        return 'Missing Item';
      case 'wrong_item':
        return 'Wrong Item';
      case 'quality':
        return 'Food Quality';
      case 'late_delivery':
        return 'Late Delivery';
      case 'never_delivered':
        return 'Never Delivered';
      case 'overcharged':
        return 'Overcharged';
      default:
        return 'Other';
    }
  }
}
