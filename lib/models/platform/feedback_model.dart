class AppFeedback {
  final String id;
  final String userId;
  final String type;
  final String message;
  final int? rating;
  final String? appVersion;
  final String? deviceInfo;
  final String? screenshotUrl;
  final String status;
  final String? adminResponse;
  final DateTime createdAt;

  AppFeedback({
    required this.id,
    required this.userId,
    required this.type,
    required this.message,
    this.rating,
    this.appVersion,
    this.deviceInfo,
    this.screenshotUrl,
    this.status = 'new',
    this.adminResponse,
    required this.createdAt,
  });

  factory AppFeedback.fromJson(Map<String, dynamic> json) {
    return AppFeedback(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      type: json['type'] as String,
      message: json['message'] as String,
      rating: json['rating'] as int?,
      appVersion: json['app_version'] as String?,
      deviceInfo: json['device_info'] as String?,
      screenshotUrl: json['screenshot_url'] as String?,
      status: json['status'] as String? ?? 'new',
      adminResponse: json['admin_response'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'type': type,
    'message': message,
    'rating': rating,
    'app_version': appVersion,
    'device_info': deviceInfo,
    'screenshot_url': screenshotUrl,
    'status': status,
    'admin_response': adminResponse,
  };

  static const feedbackTypes = [
    'bug',
    'feature',
    'compliment',
    'complaint',
    'other',
  ];

  String get typeLabel {
    switch (type) {
      case 'bug':
        return 'Bug Report';
      case 'feature':
        return 'Feature Request';
      case 'compliment':
        return 'Compliment';
      case 'complaint':
        return 'Complaint';
      default:
        return 'Other';
    }
  }

  String get typeEmoji {
    switch (type) {
      case 'bug':
        return '🐛';
      case 'feature':
        return '💡';
      case 'compliment':
        return '⭐';
      case 'complaint':
        return '😞';
      default:
        return '📝';
    }
  }
}
