import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/customer_vehicle.dart';

class CustomerVehicleService {
  final SupabaseClient _supabase;

  static const _table = 'customer_vehicles';
  static const _bucket = 'vehicle-photos';

  CustomerVehicleService({required SupabaseClient supabase})
      : _supabase = supabase;

  String get _userId {
    final id = _supabase.auth.currentUser?.id;
    if (id == null) throw Exception('Not authenticated');
    return id;
  }

  Future<List<CustomerVehicle>> getMyVehicles() async {
    final rows = await _supabase
        .from(_table)
        .select()
        .eq('customer_id', _userId)
        .eq('is_active', true)
        .order('is_default', ascending: false)
        .order('created_at', ascending: true);
    return (rows as List).map((r) => CustomerVehicle.fromMap(r)).toList();
  }

  Future<CustomerVehicle> addVehicle({
    required String make,
    required String model,
    required String vehicleType,
    String? nickname,
    int? year,
    String? color,
    String? licensePlate,
    String? photoUrl,
    bool isDefault = false,
  }) async {
    final uid = _userId;

    if (isDefault) await _clearDefault(uid);

    final row = await _supabase
        .from(_table)
        .insert({
          'customer_id': uid,
          'make': make,
          'model': model,
          'vehicle_type': vehicleType,
          if (nickname != null) 'nickname': nickname,
          if (year != null) 'year': year,
          if (color != null) 'color': color,
          if (licensePlate != null) 'license_plate': licensePlate,
          if (photoUrl != null) 'photo_url': photoUrl,
          'is_default': isDefault,
          'is_active': true,
        })
        .select()
        .single();
    return CustomerVehicle.fromMap(row);
  }

  Future<CustomerVehicle> updateVehicle(
    String vehicleId,
    Map<String, dynamic> data,
  ) async {
    final uid = _userId;
    if (data['is_default'] == true) await _clearDefault(uid);
    final row = await _supabase
        .from(_table)
        .update({...data, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', vehicleId)
        .eq('customer_id', uid)
        .select()
        .single();
    return CustomerVehicle.fromMap(row);
  }

  Future<void> deleteVehicle(String vehicleId) async {
    await _supabase
        .from(_table)
        .update({'is_active': false, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', vehicleId)
        .eq('customer_id', _userId);
  }

  Future<void> setDefault(String vehicleId) async {
    final uid = _userId;
    await _clearDefault(uid);
    await _supabase
        .from(_table)
        .update({'is_default': true, 'updated_at': DateTime.now().toIso8601String()})
        .eq('id', vehicleId)
        .eq('customer_id', uid);
  }

  Future<String?> uploadPhoto(String vehicleId, Uint8List bytes) async {
    final uid = _userId;
    final path = 'customers/$uid/$vehicleId.jpg';
    await _supabase.storage.from(_bucket).uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true),
        );
    return _supabase.storage.from(_bucket).getPublicUrl(path);
  }

  Future<void> _clearDefault(String uid) async {
    await _supabase
        .from(_table)
        .update({'is_default': false})
        .eq('customer_id', uid)
        .eq('is_default', true);
  }
}
