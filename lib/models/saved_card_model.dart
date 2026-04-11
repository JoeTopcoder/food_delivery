class SavedCard {
  final String id;
  final String userId;
  final String cardBrand;
  final String lastFour;
  final String cardholderName;
  final String email;
  final String phone;
  final bool isDefault;
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
    required this.createdAt,
  });

  factory SavedCard.fromJson(Map<String, dynamic> json) => SavedCard(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    cardBrand: json['card_brand'] as String,
    lastFour: json['last_four'] as String,
    cardholderName: json['cardholder_name'] as String,
    email: json['email'] as String,
    phone: json['phone'] as String,
    isDefault: json['is_default'] as bool? ?? false,
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
}
