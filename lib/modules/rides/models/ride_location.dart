class RideLocation {
  final String id;
  final String rideId;
  final String driverId;
  final double lat;
  final double lng;
  final double? heading;
  final double? speed;
  final DateTime createdAt;

  RideLocation({
    required this.id,
    required this.rideId,
    required this.driverId,
    required this.lat,
    required this.lng,
    this.heading,
    this.speed,
    required this.createdAt,
  });

  factory RideLocation.fromJson(Map<String, dynamic> json) {
    return RideLocation(
      id: json['id'] as String,
      rideId: json['ride_id'] as String,
      driverId: json['driver_id'] as String,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      heading: json['heading'] != null
          ? (json['heading'] as num).toDouble()
          : null,
      speed: json['speed'] != null ? (json['speed'] as num).toDouble() : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'ride_id': rideId,
    'driver_id': driverId,
    'lat': lat,
    'lng': lng,
    'heading': heading,
    'speed': speed,
    'created_at': createdAt.toIso8601String(),
  };

  RideLocation copyWith({
    String? id,
    String? rideId,
    String? driverId,
    double? lat,
    double? lng,
    double? heading,
    double? speed,
    DateTime? createdAt,
  }) {
    return RideLocation(
      id: id ?? this.id,
      rideId: rideId ?? this.rideId,
      driverId: driverId ?? this.driverId,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      heading: heading ?? this.heading,
      speed: speed ?? this.speed,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
