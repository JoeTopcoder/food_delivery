class ProviderAvailability {
  final String id;
  final String providerId;
  final int dayOfWeek; // 0 = Sunday, 6 = Saturday
  final String startTime; // e.g. "09:00"
  final String endTime;   // e.g. "17:00"
  final bool isActive;

  const ProviderAvailability({
    required this.id,
    required this.providerId,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    required this.isActive,
  });

  factory ProviderAvailability.fromMap(Map<String, dynamic> map) {
    return ProviderAvailability(
      id: map['id'] as String,
      providerId: map['provider_id'] as String,
      dayOfWeek: map['day_of_week'] as int,
      startTime: map['start_time'] as String,
      endTime: map['end_time'] as String,
      isActive: map['is_active'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    if (id.isNotEmpty) 'id': id,
    'provider_id': providerId,
    'day_of_week': dayOfWeek,
    'start_time': startTime,
    'end_time': endTime,
    'is_active': isActive,
  };

  String get dayName =>
      ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'][dayOfWeek];

  ProviderAvailability copyWith({
    String? id,
    String? providerId,
    int? dayOfWeek,
    String? startTime,
    String? endTime,
    bool? isActive,
  }) {
    return ProviderAvailability(
      id: id ?? this.id,
      providerId: providerId ?? this.providerId,
      dayOfWeek: dayOfWeek ?? this.dayOfWeek,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      isActive: isActive ?? this.isActive,
    );
  }
}
