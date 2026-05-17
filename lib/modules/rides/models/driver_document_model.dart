class DriverDocument {
  final String id;
  final String driverId;
  final String type; // e.g. 'license', 'registration', 'insurance'
  final String url;
  final bool isVerified;
  final DateTime uploadedAt;

  DriverDocument({
    required this.id,
    required this.driverId,
    required this.type,
    required this.url,
    required this.isVerified,
    required this.uploadedAt,
  });

  factory DriverDocument.fromJson(Map<String, dynamic> json) {
    return DriverDocument(
      id: json['id'] as String,
      driverId: json['driver_id'] as String,
      type: json['type'] as String,
      url: json['url'] as String,
      isVerified: json['is_verified'] as bool,
      uploadedAt: DateTime.parse(json['uploaded_at'] as String),
    );
  }
}
