class SavedCard {
  final String id;
  final String userId;
  final String cardBrand;
  final String lastFour;
  final String cardholderName;
  final String email;
  final String phone;
  final bool isDefault;
  final String status; // 'pending', 'verified', 'failed'
  final String? verificationId;
  final DateTime? verificationExpiresAt;
  final int verificationAttempts;
  final DateTime createdAt;

  const SavedCard({
    required this.id,
    required this.userId,
    required this.cardBrand,
    required this.lastFour,
    required this.cardholderName,
    required this.email,
    required this.phone,
    this.isDefault = false,
    this.status = 'verified',
    this.verificationId,
    this.verificationExpiresAt,
    this.verificationAttempts = 0,
    required this.createdAt,
  });

  factory SavedCard.fromJson(Map<String, dynamic> json) => SavedCard(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    cardBrand: json['card_brand'] as String,
    lastFour: json['last_four'] as String,
    cardholderName: json['cardholder_name'] as String? ?? '',
    email: json['email'] as String? ?? '',
    phone: json['phone'] as String? ?? '',
    isDefault: json['is_default'] as bool? ?? false,
    status: json['status'] as String? ?? 'verified',
    verificationId: json['verification_id'] as String?,
    verificationExpiresAt: json['verification_expires_at'] != null
        ? DateTime.parse(json['verification_expires_at'] as String)
        : null,
    verificationAttempts: json['verification_attempts'] as int? ?? 0,
    createdAt: DateTime.parse(json['created_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'card_brand': cardBrand,
    'last_four': lastFour,
    'cardholder_name': cardholderName,
    'email': email,
    'phone': phone,
    'is_default': isDefault,
    'status': status,
    'verification_id': verificationId,
    'verification_expires_at': verificationExpiresAt?.toIso8601String(),
    'verification_attempts': verificationAttempts,
  };

  String get displayBrand {
    switch (cardBrand.toLowerCase()) {
      case 'visa':
        return 'VISA';
      case 'mastercard':
        return 'MC';
      case 'keycard':
        return 'KEYCARD';
      default:
        return cardBrand.toUpperCase();
    }
  }

  String get maskedNumber => '•••• $lastFour';

  bool get isPending => status == 'pending';
  bool get isVerified => status == 'verified';
  bool get isFailed => status == 'failed';

  bool get isExpired =>
      verificationExpiresAt != null &&
      DateTime.now().toUtc().isAfter(verificationExpiresAt!.toUtc());

  Duration? get timeRemaining {
    if (verificationExpiresAt == null) return null;
    final remaining = verificationExpiresAt!.toUtc().difference(
      DateTime.now().toUtc(),
    );
    return remaining.isNegative ? Duration.zero : remaining;
  }
}
