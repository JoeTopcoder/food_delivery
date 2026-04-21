import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_constants.dart';
import '../../../config/supabase_config.dart';
import '../models/onboarding_role.dart';

class OnboardingService {
  OnboardingService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  String? get currentUserId => _client.auth.currentUser?.id;

  Future<void> sendOtp(String phone) async {
    final normalizedPhone = _normalizePhone(phone);
    try {
      await _client.auth.signInWithOtp(
        phone: normalizedPhone,
        shouldCreateUser: true,
      );
    } on AuthException catch (e) {
      final message = e.message.toLowerCase();
      if (message.contains('sms') || message.contains('phone')) {
        throw Exception(
          'Could not send OTP. Check phone auth provider and SMS settings, then try again with a full number like +1345XXXXXXX.',
        );
      }
      rethrow;
    }
  }

  String _normalizePhone(String input) {
    final raw = input.trim();
    if (raw.isEmpty) {
      throw Exception('Enter your phone number first.');
    }

    if (raw.startsWith('00')) {
      return '+${raw.substring(2).replaceAll(RegExp(r'[^0-9]'), '')}';
    }

    if (raw.startsWith('+')) {
      final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length < 8) {
        throw Exception('Enter a valid phone number in international format.');
      }
      return '+$digits';
    }

    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 7) {
      return '+1345$digits';
    }
    if (digits.length == 10) {
      return '+1$digits';
    }
    if (digits.length == 11 && digits.startsWith('1')) {
      return '+$digits';
    }
    if (digits.length >= 8) {
      return '+$digits';
    }

    throw Exception('Enter a valid phone number, for example +1345XXXXXXX.');
  }

  Future<AuthResponse> verifyOtp({
    required String phone,
    required String token,
  }) {
    return _client.auth.verifyOTP(
      type: OtpType.sms,
      phone: phone,
      token: token,
    );
  }

  Future<void> ensureUserRecord({
    required String userId,
    required OnboardingRole role,
    String? phone,
    String? email,
    String? name,
    bool onboardingCompleted = false,
  }) async {
    await _client.from(AppConstants.tableUsers).upsert({
      'id': userId,
      'role': role.dbRole,
      'phone': phone,
      'email': email,
      'name': name,
      'onboarding_completed': onboardingCompleted,
      'updated_at': DateTime.now().toIso8601String(),
    });

    if (role == OnboardingRole.driver) {
      await _client.from(AppConstants.tableDrivers).upsert({
        'user_id': userId,
        'status': 'pending',
        'documents_uploaded': false,
        'updated_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<void> completeCustomerOnboarding({
    required String userId,
    required String phone,
  }) async {
    await ensureUserRecord(
      userId: userId,
      role: OnboardingRole.customer,
      phone: phone,
      onboardingCompleted: true,
    );
  }

  Future<void> saveDriverProfile({
    required String userId,
    String? phone,
    String? name,
    String? email,
    String? vehicleType,
    String? licensePlate,
    bool documentsUploaded = false,
  }) async {
    await ensureUserRecord(
      userId: userId,
      role: OnboardingRole.driver,
      phone: phone,
      email: email,
      name: name,
      onboardingCompleted: false,
    );

    await _client.from(AppConstants.tableDrivers).upsert({
      'user_id': userId,
      'vehicle_type': vehicleType,
      'license_plate': licensePlate,
      'status': 'pending',
      'documents_uploaded': documentsUploaded,
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> saveRestaurantDraft({
    required String userId,
    required String businessName,
    required String phone,
    String? address,
    int onboardingStep = 1,
    bool goLive = false,
    String? menuImageUrl,
    List<Map<String, dynamic>> quickItems = const [],
  }) async {
    await ensureUserRecord(
      userId: userId,
      role: OnboardingRole.restaurant,
      phone: phone,
      onboardingCompleted: goLive,
    );

    final restaurantPayload = {
      'owner_id': userId,
      'name': businessName,
      'phone': phone,
      'address': address,
      'status': goLive ? 'active' : 'draft',
      'onboarding_step': onboardingStep,
      'menu_image_url': menuImageUrl,
      'updated_at': DateTime.now().toIso8601String(),
    };

    final restaurantRow = await _client
        .from(AppConstants.tableRestaurants)
        .upsert(restaurantPayload)
        .select('id')
        .single();

    final restaurantId = restaurantRow['id'] as String;
    if (quickItems.isNotEmpty) {
      final rows = quickItems
          .where((e) => (e['name'] as String?)?.trim().isNotEmpty == true)
          .map(
            (e) => {
              'restaurant_id': restaurantId,
              'name': e['name'],
              'price': e['price'] ?? 0,
              'image_url': e['image_url'],
            },
          )
          .toList();
      if (rows.isNotEmpty) {
        await _client.from('menu_items').insert(rows);
      }
    }
  }

  Future<void> markOnboardingCompleted(String userId) async {
    await _client
        .from(AppConstants.tableUsers)
        .update({
          'onboarding_completed': true,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', userId);
  }
}

final onboardingServiceProvider = Provider<OnboardingService>((ref) {
  return OnboardingService();
});
