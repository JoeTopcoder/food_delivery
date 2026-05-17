class RideMessage {
  final String id;
  final String rideId;
  final String senderId;
  final String receiverId;
  final String message;
  final bool isRead;
  final DateTime createdAt;

  RideMessage({
    required this.id,
    required this.rideId,
    required this.senderId,
    required this.receiverId,
    required this.message,
    required this.isRead,
    required this.createdAt,
  });

  factory RideMessage.fromJson(Map<String, dynamic> json) {
    return RideMessage(
      id: json['id'] as String,
      rideId: json['ride_id'] as String,
      senderId: json['sender_id'] as String,
      receiverId: json['receiver_id'] as String,
      message: json['message'] as String,
      isRead: json['is_read'] as bool? ?? false,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ride_id': rideId,
    'sender_id': senderId,
    'receiver_id': receiverId,
    'message': message,
    'is_read': isRead,
    'created_at': createdAt.toIso8601String(),
  };

  RideMessage copyWith({
    String? id,
    String? rideId,
    String? senderId,
    String? receiverId,
    String? message,
    bool? isRead,
    DateTime? createdAt,
  }) {
    return RideMessage(
      id: id ?? this.id,
      rideId: rideId ?? this.rideId,
      senderId: senderId ?? this.senderId,
      receiverId: receiverId ?? this.receiverId,
      message: message ?? this.message,
      isRead: isRead ?? this.isRead,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
