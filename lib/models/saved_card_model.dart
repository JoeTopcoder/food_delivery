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
  final String? stripePaymentMethodId;
  final String? stripeCustomerId;
  final int? expMonth;
  final int? expYear;
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
    this.stripePaymentMethodId,
    this.stripeCustomerId,
    this.expMonth,
    this.expYear,
    required this.createdAt,
  });

  factory SavedCard.fromJson(Map<String, dynamic> json) => SavedCard(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    cardBrand: json['card_brand'] as String? ?? '',
    lastFour: json['last_four'] as String? ?? '',
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
    stripePaymentMethodId: json['stripe_payment_method_id'] as String?,
    stripeCustomerId: json['stripe_customer_id'] as String?,
    expMonth: json['exp_month'] as int?,
    expYear: json['exp_year'] as int?,
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
    'stripe_payment_method_id': stripePaymentMethodId,
    'stripe_customer_id': stripeCustomerId,
    'exp_month': expMonth,
    'exp_year': expYear,
  };

  String get displayBrand {
    switch (cardBrand.toLowerCase()) {
      case 'visa':
        return 'VISA';
      case 'mastercard':
        return 'MC';
      case 'keycard':
        return 'KEYCARD';
      case 'amex':
      case 'american_express':
        return 'AMEX';
      case 'discover':
        return 'DISCOVER';
      case 'lunipay':
      case '':
      case 'card':
      case 'unknown':
        // Don't expose the processor name to the cardholder.
        return 'CARD';
      default:
        return cardBrand.toUpperCase();
    }
  }

  String get maskedNumber => '•••• $lastFour';

  String get expiryDisplay {
    if (expMonth != null && expYear != null) {
      final m = expMonth.toString().padLeft(2, '0');
      final y = (expYear! % 100).toString().padLeft(2, '0');
      return '$m/$y';
    }
    return '';
  }

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
