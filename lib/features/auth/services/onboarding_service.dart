import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../config/app_constants.dart';
import '../../../config/supabase_config.dart';
import '../../../utils/app_logger.dart';
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
    try {
      await ensureUserRecord(
        userId: userId,
        role: OnboardingRole.driver,
        phone: phone,
        email: email,
        name: name,
        onboardingCompleted: false,
      );
    } catch (e) {
      AppLogger.warning('saveDriverProfile.ensureUserRecord failed: $e');
    }

    // documents_status is JSONB on remote — never write a plain string.
    // Build a JSON object that matches the column shape.
    final docsJson = documentsUploaded
        ? {
            'license': 'verified',
            'registration': 'verified',
            'insurance': 'verified',
          }
        : {
            'license': 'pending',
            'registration': 'pending',
            'insurance': 'pending',
          };

    final basePayload = <String, dynamic>{
      'user_id': userId,
      'updated_at': DateTime.now().toIso8601String(),
    };
    final extendedPayload = <String, dynamic>{
      ...basePayload,
      if (vehicleType != null) 'vehicle_type': vehicleType,
      if (licensePlate != null) 'license_number': licensePlate,
      'documents_status': docsJson,
    };

    try {
      final existing = await _client
          .from(AppConstants.tableDrivers)
          .select('id')
          .eq('user_id', userId)
          .maybeSingle();

      if (existing == null) {
        try {
          await _client.from(AppConstants.tableDrivers).insert(extendedPayload);
        } catch (e) {
          AppLogger.warning(
            'drivers extended insert failed, retrying base: $e',
          );
          await _client.from(AppConstants.tableDrivers).insert(basePayload);
        }
      } else {
        try {
          await _client
              .from(AppConstants.tableDrivers)
              .update(extendedPayload)
              .eq('user_id', userId);
        } catch (e) {
          AppLogger.warning(
            'drivers extended update failed, retrying base: $e',
          );
          await _client
              .from(AppConstants.tableDrivers)
              .update(basePayload)
              .eq('user_id', userId);
        }
      }
    } catch (e) {
      AppLogger.error('saveDriverProfile drivers write failed: $e');
      // Do not rethrow — onboarding screen should keep flowing.
    }
  }

  Future<void> saveRestaurantDraft({
    required String userId,
    required String businessName,
    required String phone,
    String? address,
    String? description,
    String? cuisineType,
    String? email,
    String? openingTime,
    String? closingTime,
    String? storeType,
    String? bankName,
    String? bankAccountHolder,
    String? bankAccountNumber,
    String? bankAccountType,
    String? bankBranch,
    int onboardingStep = 1,
    bool goLive = false,
    String? menuImageUrl,
    List<Map<String, dynamic>> quickItems = const [],
  }) async {
    // Best-effort sync of the user row. Never fail onboarding if this
    // throws (RLS, missing column, etc.) — the trigger or a later sign-in
    // will recover.
    try {
      await ensureUserRecord(
        userId: userId,
        role: OnboardingRole.restaurant,
        phone: phone,
        onboardingCompleted: goLive,
      );
    } catch (e) {
      AppLogger.warning('ensureUserRecord (restaurant) failed: $e');
    }

    // Base columns always present in schema.
    final basePayload = <String, dynamic>{
      'owner_id': userId,
      'name': businessName.isNotEmpty ? businessName : 'My Restaurant',
      'updated_at': DateTime.now().toIso8601String(),
    };
    if (phone.isNotEmpty) basePayload['phone'] = phone;
    if (address != null && address.isNotEmpty) basePayload['address'] = address;
    if (description != null && description.isNotEmpty) basePayload['description'] = description;
    if (cuisineType != null && cuisineType.isNotEmpty) basePayload['cuisine_type'] = cuisineType;
    if (email != null && email.isNotEmpty) basePayload['email'] = email;
    if (openingTime != null && openingTime.isNotEmpty) basePayload['opening_time'] = openingTime;
    if (closingTime != null && closingTime.isNotEmpty) basePayload['closing_time'] = closingTime;
    if (storeType != null && storeType.isNotEmpty) basePayload['store_type'] = storeType;
    if (bankName != null && bankName.isNotEmpty) basePayload['bank_name'] = bankName;
    if (bankAccountHolder != null && bankAccountHolder.isNotEmpty) basePayload['bank_account_holder'] = bankAccountHolder;
    if (bankAccountNumber != null && bankAccountNumber.isNotEmpty) basePayload['bank_account_number'] = bankAccountNumber;
    if (bankAccountType != null && bankAccountType.isNotEmpty) basePayload['bank_account_type'] = bankAccountType;
    if (bankBranch != null && bankBranch.isNotEmpty) basePayload['bank_branch'] = bankBranch;

    // onboarding_step is a core column — always write it in base payload.
    basePayload['onboarding_step'] = onboardingStep;

    // Build extended payload for optional columns (status, menu_image_url).
    final extendedPayload = Map<String, dynamic>.from(basePayload);
    // Always 'draft' — DB check constraint only allows 'draft'/'active'.
    extendedPayload['status'] = 'draft';
    if (menuImageUrl != null) extendedPayload['menu_image_url'] = menuImageUrl;

    // Look up an existing restaurant for this owner. We avoid Supabase's
    // upsert (which requires a unique constraint we don't have on owner_id)
    // and explicitly insert-or-update to keep things deterministic.
    String? restaurantId;
    try {
      final existing = await _client
          .from(AppConstants.tableRestaurants)
          .select('id')
          .eq('owner_id', userId)
          .limit(1)
          .maybeSingle();
      restaurantId = existing?['id'] as String?;
    } catch (e) {
      AppLogger.warning('Restaurant lookup failed (continuing): $e');
      restaurantId = null;
    }

    Future<Map<String, dynamic>?> writeRestaurant(
      Map<String, dynamic> payload,
    ) async {
      if (restaurantId != null) {
        return await _client
            .from(AppConstants.tableRestaurants)
            .update(payload)
            .eq('id', restaurantId)
            .select('id')
            .maybeSingle();
      }
      return await _client
          .from(AppConstants.tableRestaurants)
          .insert(payload)
          .select('id')
          .maybeSingle();
    }

    Map<String, dynamic>? restaurantRow;
    try {
      restaurantRow = await writeRestaurant(extendedPayload);
    } on PostgrestException catch (e) {
      AppLogger.warning(
        'Extended restaurant write failed (${e.code}: ${e.message}); '
        'retrying with base payload',
      );
      try {
        restaurantRow = await writeRestaurant(basePayload);
      } catch (e2) {
        AppLogger.error('Base restaurant write also failed: $e2');
        rethrow;
      }
    }

    final newRestaurantId = restaurantRow?['id'] as String? ?? restaurantId;
    if (newRestaurantId != null && quickItems.isNotEmpty) {
      final rows = quickItems
          .where((e) => (e['name'] as String?)?.trim().isNotEmpty == true)
          .map(
            (e) => {
              'restaurant_id': newRestaurantId,
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
