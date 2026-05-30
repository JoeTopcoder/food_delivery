import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/address_model.dart';

class AddressService {
  final SupabaseClient _client;
  AddressService(this._client);

  Future<List<UserAddress>> getAddresses(String userId) async {
    final res = await _client
        .from('user_addresses')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false);
    return (res as List).map((e) => UserAddress.fromJson(e)).toList();
  }

  Future<UserAddress> addAddress({
    required String userId,
    required String label,
    required String address,
    double? latitude,
    double? longitude,
    bool isDefault = false,
  }) async {
    if (isDefault) {
      await _client
          .from('user_addresses')
          .update({'is_default': false})
          .eq('user_id', userId);
    }
    final res = await _client
        .from('user_addresses')
        .insert({
          'user_id': userId,
          'label': label,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
          'is_default': isDefault,
        })
        .select()
        .single();
    return UserAddress.fromJson(res);
  }

  Future<void> setDefault(String addressId, String userId) async {
    try {
      await _client
          .from('user_addresses')
          .update({'is_default': false})
          .eq('user_id', userId);
      await _client
          .from('user_addresses')
          .update({'is_default': true})
          .eq('id', addressId);
    } catch (e) {
      // If second update fails, at least try to restore the target as default
      try {
        await _client
            .from('user_addresses')
            .update({'is_default': true})
            .eq('id', addressId);
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> deleteAddress(String addressId) async {
    await _client.from('user_addresses').delete().eq('id', addressId);
  }

  Future<void> updateAddress({
    required String addressId,
    required String label,
    required String address,
    double? latitude,
    double? longitude,
  }) async {
    await _client
        .from('user_addresses')
        .update({
          'label': label,
          'address': address,
          'latitude': latitude,
          'longitude': longitude,
        })
        .eq('id', addressId);
  }
}
