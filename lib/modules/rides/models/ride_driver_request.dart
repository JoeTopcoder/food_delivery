enum RideDriverRequestStatus {
  pending,
  offered,
  accepted,
  rejected,
  expired;

  static RideDriverRequestStatus fromString(String value) {
    return RideDriverRequestStatus.values.firstWhere(
      (e) => e.name == value.toLowerCase(),
      orElse: () => RideDriverRequestStatus.expired,
    );
  }
}

class RideDriverRequest {
  final String id;
  final String rideId;
  final String driverId;
  final RideDriverRequestStatus status;
  final DateTime sentAt;
  final DateTime? respondedAt;
  final DateTime expiresAt;

  RideDriverRequest({
    required this.id,
    required this.rideId,
    required this.driverId,
    required this.status,
    required this.sentAt,
    this.respondedAt,
    required this.expiresAt,
  });

  factory RideDriverRequest.fromJson(Map<String, dynamic> json) {
    return RideDriverRequest(
      id: json['id'] as String,
      rideId: json['ride_id'] as String,
      driverId: json['driver_id'] as String,
      status: RideDriverRequestStatus.fromString(
        json['status'] as String? ?? 'pending',
      ),
      sentAt: DateTime.parse(json['sent_at'] as String),
      respondedAt: json['responded_at'] != null
          ? DateTime.parse(json['responded_at'] as String)
          : null,
      expiresAt: DateTime.parse(json['expires_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ride_id': rideId,
    'driver_id': driverId,
    'status': status.name,
    'sent_at': sentAt.toIso8601String(),
    'responded_at': respondedAt?.toIso8601String(),
    'expires_at': expiresAt.toIso8601String(),
  };

  RideDriverRequest copyWith({
    String? id,
    String? rideId,
    String? driverId,
    RideDriverRequestStatus? status,
    DateTime? sentAt,
    DateTime? respondedAt,
    DateTime? expiresAt,
  }) {
    return RideDriverRequest(
      id: id ?? this.id,
      rideId: rideId ?? this.rideId,
      driverId: driverId ?? this.driverId,
      status: status ?? this.status,
      sentAt: sentAt ?? this.sentAt,
      respondedAt: respondedAt ?? this.respondedAt,
      expiresAt: expiresAt ?? this.expiresAt,
    );
  }

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  int get secondsUntilExpiry {
    final secondsLeft = expiresAt.difference(DateTime.now()).inSeconds;
    return secondsLeft > 0 ? secondsLeft : 0;
  }
}
