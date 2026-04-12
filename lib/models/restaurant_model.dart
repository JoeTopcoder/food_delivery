import 'package:intl/intl.dart';
import 'package:json_annotation/json_annotation.dart';
import '../utils/est_datetime.dart';

part 'restaurant_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class Restaurant {
  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? imageUrl;
  final String? phone;
  final String? email;
  final String? address;
  final double? latitude;
  final double? longitude;
  final String? cuisineType;
  final double? rating;
  final int? reviewCount;
  final double? deliveryFee;
  final int? estimatedDeliveryTime; // in minutes
  final bool isOpen;
  final String? openingTime;
  final String? closingTime;
  final List<String>? tags;
  final bool isVerified;
  final String? bankName;
  final String? bankBranch;
  final String? bankAccountNumber;
  final String? bankAccountHolder;
  final String? bankAccountType;
  final double? commissionRate;
  final Map<String, dynamic>? operatingHours;
  final double? totalEarnings;
  final double? totalPaidOut;
  final DateTime createdAt;
  final DateTime? updatedAt;

  Restaurant({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.imageUrl,
    this.phone,
    this.email,
    this.address,
    this.latitude,
    this.longitude,
    this.cuisineType,
    this.rating,
    this.reviewCount,
    this.deliveryFee,
    this.estimatedDeliveryTime,
    this.isOpen = true,
    this.openingTime,
    this.closingTime,
    this.tags,
    this.isVerified = false,
    this.bankName,
    this.bankBranch,
    this.bankAccountNumber,
    this.bankAccountHolder,
    this.bankAccountType,
    this.commissionRate,
    this.operatingHours,
    this.totalEarnings,
    this.totalPaidOut,
    required this.createdAt,
    this.updatedAt,
  });

  factory Restaurant.fromJson(Map<String, dynamic> json) =>
      _$RestaurantFromJson(json);
  Map<String, dynamic> toJson() => _$RestaurantToJson(this);

  Restaurant copyWith({
    String? id,
    String? ownerId,
    String? name,
    String? description,
    String? imageUrl,
    String? phone,
    String? email,
    String? address,
    double? latitude,
    double? longitude,
    String? cuisineType,
    double? rating,
    int? reviewCount,
    double? deliveryFee,
    int? estimatedDeliveryTime,
    bool? isOpen,
    String? openingTime,
    String? closingTime,
    List<String>? tags,
    bool? isVerified,
    String? bankName,
    String? bankBranch,
    String? bankAccountNumber,
    String? bankAccountHolder,
    String? bankAccountType,
    double? commissionRate,
    Map<String, dynamic>? operatingHours,
    double? totalEarnings,
    double? totalPaidOut,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Restaurant(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      name: name ?? this.name,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      cuisineType: cuisineType ?? this.cuisineType,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      estimatedDeliveryTime:
          estimatedDeliveryTime ?? this.estimatedDeliveryTime,
      isOpen: isOpen ?? this.isOpen,
      openingTime: openingTime ?? this.openingTime,
      closingTime: closingTime ?? this.closingTime,
      tags: tags ?? this.tags,
      isVerified: isVerified ?? this.isVerified,
      bankName: bankName ?? this.bankName,
      bankBranch: bankBranch ?? this.bankBranch,
      bankAccountNumber: bankAccountNumber ?? this.bankAccountNumber,
      bankAccountHolder: bankAccountHolder ?? this.bankAccountHolder,
      bankAccountType: bankAccountType ?? this.bankAccountType,
      commissionRate: commissionRate ?? this.commissionRate,
      operatingHours: operatingHours ?? this.operatingHours,
      totalEarnings: totalEarnings ?? this.totalEarnings,
      totalPaidOut: totalPaidOut ?? this.totalPaidOut,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Whether the restaurant is open right now based on its operating hours.
  /// All comparisons use Eastern Standard Time (UTC-5).
  /// Falls back to the manual [isOpen] flag when no schedule is set.
  bool get isCurrentlyOpen {
    if (!isOpen) return false; // manual override always wins

    if (operatingHours == null || operatingHours!.isEmpty) {
      // No schedule — use legacy openingTime / closingTime if available
      if (openingTime != null && closingTime != null) {
        return _isWithinTimeRange(openingTime!, closingTime!);
      }
      return isOpen;
    }

    final todayHours = _todayHours();
    if (todayHours == null) return isOpen;

    final dayIsOpen = todayHours['is_open'] ?? true;
    if (dayIsOpen != true) return false;

    final open = todayHours['open'] as String?;
    final close = todayHours['close'] as String?;
    if (open == null || close == null) return true;

    return _isWithinTimeRange(open, close);
  }

  /// Returns the operating-hours map for the current EST day, or null.
  Map<String, dynamic>? _todayHours() {
    if (operatingHours == null || operatingHours!.isEmpty) return null;
    final now = EstDateTime.now();
    final dayName = DateFormat('EEEE').format(now).toLowerCase();
    final dayData = operatingHours![dayName];
    return dayData is Map ? Map<String, dynamic>.from(dayData) : null;
  }

  /// Returns the opening time (HH:mm) for a given EST [day] name,
  /// or falls back to the legacy [openingTime].
  String? _openTimeForDay(String day) {
    final dayData = operatingHours?[day];
    if (dayData is Map) return dayData['open'] as String?;
    return openingTime;
  }

  /// The earliest DateTime (EST) the customer can schedule an order when
  /// the restaurant is currently closed.
  /// Rule: next day, 1 hour after opening time.
  DateTime? get nextSchedulableTime {
    final now = EstDateTime.now();
    final days = [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ];
    final todayIdx = now.weekday - 1; // DateTime.weekday: 1=Mon

    // Look up to 7 days ahead for the next open day
    for (int offset = 1; offset <= 7; offset++) {
      final idx = (todayIdx + offset) % 7;
      final dayName = days[idx];

      // Check if this day is marked open
      if (operatingHours != null && operatingHours!.isNotEmpty) {
        final dayData = operatingHours![dayName];
        if (dayData is Map && dayData['is_open'] == false) continue;
      }

      final openStr = _openTimeForDay(dayName);
      if (openStr == null) continue;

      final parts = openStr.split(':');
      if (parts.length < 2) continue;

      final openHour = int.parse(parts[0]);
      final openMinute = int.parse(parts[1]);

      // Build the date for that future day
      final targetDate = now.add(Duration(days: offset));
      // 1 hour after opening
      return DateTime(
        targetDate.year,
        targetDate.month,
        targetDate.day,
        openHour + 1,
        openMinute,
      );
    }
    return null;
  }

  /// Formatted string describing when the restaurant next opens (EST).
  String get nextOpenLabel {
    final t = nextSchedulableTime;
    if (t == null) return 'Unavailable';
    // Subtract the 1-hour buffer to show actual opening time
    final openTime = t.subtract(const Duration(hours: 1));
    return 'Opens ${DateFormat('EEEE').format(openTime)} at '
        '${DateFormat('h:mm a').format(openTime)}';
  }

  /// Today's hours formatted as "8:00 AM - 10:00 PM" or null.
  String? get formattedTodayHours {
    final hours = _todayHours();
    if (hours != null) {
      final open = hours['open'] as String?;
      final close = hours['close'] as String?;
      if (open != null && close != null) {
        return '${_formatTime(open)} - ${_formatTime(close)}';
      }
    }
    // Fall back to legacy fields
    if (openingTime != null && closingTime != null) {
      return '${_formatTime(openingTime!)} - ${_formatTime(closingTime!)}';
    }
    return null;
  }

  /// Convert "HH:mm" (24-hour) to "h:mm AM/PM".
  static String _formatTime(String hhmm) {
    final parts = hhmm.split(':');
    if (parts.length < 2) return hhmm;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    final dt = DateTime(2000, 1, 1, h, m);
    return DateFormat('h:mm a').format(dt);
  }

  bool _isWithinTimeRange(String openStr, String closeStr) {
    final now = EstDateTime.now();
    final parts1 = openStr.split(':');
    final parts2 = closeStr.split(':');
    if (parts1.length < 2 || parts2.length < 2) return true;

    final openMin = int.parse(parts1[0]) * 60 + int.parse(parts1[1]);
    final closeMin = int.parse(parts2[0]) * 60 + int.parse(parts2[1]);
    final nowMin = now.hour * 60 + now.minute;

    if (closeMin > openMin) {
      return nowMin >= openMin && nowMin < closeMin;
    } else {
      // Wraps past midnight (e.g. 18:00 – 02:00)
      return nowMin >= openMin || nowMin < closeMin;
    }
  }
}
