class CarServiceReview {
  final String id;
  final String bookingId;
  final String customerId;
  final String providerId;
  final int rating;
  final String? comment;
  final DateTime createdAt;

  const CarServiceReview({
    required this.id,
    required this.bookingId,
    required this.customerId,
    required this.providerId,
    required this.rating,
    this.comment,
    required this.createdAt,
  });

  factory CarServiceReview.fromMap(Map<String, dynamic> map) {
    return CarServiceReview(
      id: map['id'] as String,
      bookingId: map['booking_id'] as String,
      customerId: map['customer_id'] as String,
      providerId: map['provider_id'] as String,
      rating: map['rating'] as int,
      comment: map['comment'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'booking_id': bookingId,
    'customer_id': customerId,
    'provider_id': providerId,
    'rating': rating,
    'comment': comment,
    'created_at': createdAt.toIso8601String(),
  };
}
