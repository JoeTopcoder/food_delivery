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
      phone: _normalizePhone(phone),
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
    // Use legacySafeRole so we write 'user' for customers until migration runs.
    // Only include columns that exist in the base schema.
    final userPayload = <String, dynamic>{
      'id': userId,
      'role': role.legacySafeRole,
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (phone != null) userPayload['phone'] = phone;
    if (name != null && name.isNotEmpty) userPayload['name'] = name;
    // email is NOT NULL in base schema — use a placeholder for OTP (phone-only) users.
    userPayload['email'] = (email != null && email.isNotEmpty)
        ? email
        : '$userId@otp.fooddriver.app';

    // Try full upsert; fall back to minimal if extended columns not yet migrated.
    try {
      final extended = Map<String, dynamic>.from(userPayload);
      extended['onboarding_completed'] = onboardingCompleted;
      await _client.from(AppConstants.tableUsers).upsert(extended);
    } catch (_) {
      // onboarding_completed column may not exist yet — retry without it.
      await _client.from(AppConstants.tableUsers).upsert(userPayload);
    }

    if (role == OnboardingRole.driver) {
      // Try with extended columns; fall back to base schema columns.
      try {
        await _client.from(AppConstants.tableDrivers).upsert({
          'user_id': userId,
          'documents_status': 'pending',
          'is_available': false,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id');
      } catch (_) {
        await _client.from(AppConstants.tableDrivers).upsert({
          'user_id': userId,
          'updated_at': DateTime.now().toIso8601String(),
        }, onConflict: 'user_id');
      }
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
      if (vehicleType != null) 'vehicle_type': vehicleType,
      if (licensePlate != null) 'license_number': licensePlate,
      'documents_status': documentsUploaded ? 'approved' : 'pending',
      'updated_at': DateTime.now().toIso8601String(),
    }, onConflict: 'user_id');
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

    // Base columns always present in schema.
    final basePayload = <String, dynamic>{
      'owner_id': userId,
      'name': businessName.isNotEmpty ? businessName : 'My Restaurant',
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (phone.isNotEmpty) basePayload['phone'] = phone;
    if (address != null && address.isNotEmpty) basePayload['address'] = address;

    // Try with extended onboarding columns, fall back to base if not migrated yet.
    Map<String, dynamic> restaurantPayload = basePayload;
    try {
      final extended = Map<String, dynamic>.from(basePayload);
      extended['status'] = goLive ? 'active' : 'draft';
      extended['onboarding_step'] = onboardingStep;
      if (menuImageUrl != null) extended['menu_image_url'] = menuImageUrl;
      // Probe: run a small query first to see if columns exist.
      await _client
          .from(AppConstants.tableRestaurants)
          .select('status')
          .limit(1);
      restaurantPayload = extended;
    } catch (_) {
      // Extended columns not yet migrated — use base payload only.
    }

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
        // menu_items table may not exist until migration runs — ignore silently.
        try {
          await _client.from('menu_items').insert(rows);
        } catch (_) {}
      }
    }
  }

  Future<void> markOnboardingCompleted(String userId) async {
    try {
      await _client
          .from(AppConstants.tableUsers)
          .update({
            'onboarding_completed': true,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
    } catch (_) {
      // Column may not exist yet — non-critical, ignore.
    }
  }
}

final onboardingServiceProvider = Provider<OnboardingService>((ref) {
  return OnboardingService();
});
