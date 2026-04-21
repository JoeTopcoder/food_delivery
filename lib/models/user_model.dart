import 'package:json_annotation/json_annotation.dart';

part 'user_model.g.dart';

@JsonSerializable(fieldRename: FieldRename.snake)
class User {
  final String id;
  final String? email;
  final String? name;
  final String? phone;
  final String? profileImageUrl;
  final String role; // 'customer', 'restaurant', 'driver', 'admin'
  final bool onboardingCompleted;
  final String? address;
  final double? latitude;
  final double? longitude;
  final bool isActive;
  final String? referralCode;
  final String? referredBy;
  final DateTime createdAt;
  final DateTime? updatedAt;

  User({
    required this.id,
    this.email,
    this.name,
    this.phone,
    this.profileImageUrl,
    required this.role,
    this.onboardingCompleted = false,
    this.address,
    this.latitude,
    this.longitude,
    this.isActive = true,
    this.referralCode,
    this.referredBy,
    required this.createdAt,
    this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);

  User copyWith({
    String? id,
    String? email,
    String? name,
    String? phone,
    String? profileImageUrl,
    String? role,
    bool? onboardingCompleted,
    String? address,
    double? latitude,
    double? longitude,
    bool? isActive,
    String? referralCode,
    String? referredBy,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      profileImageUrl: profileImageUrl ?? this.profileImageUrl,
      role: role ?? this.role,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      isActive: isActive ?? this.isActive,
      referralCode: referralCode ?? this.referralCode,
      referredBy: referredBy ?? this.referredBy,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
