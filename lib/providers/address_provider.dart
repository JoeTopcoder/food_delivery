import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/address_model.dart';
import '../services/address_service.dart';

final addressServiceProvider = Provider<AddressService>((ref) {
  return AddressService(Supabase.instance.client);
});

final userAddressesProvider = FutureProvider.family<List<UserAddress>, String>((
  ref,
  userId,
) {
  return ref.watch(addressServiceProvider).getAddresses(userId);
});

/// The default address for a given user (first where is_default == true).
final defaultAddressProvider = FutureProvider.family<UserAddress?, String>((
  ref,
  userId,
) async {
  final addresses = await ref
      .watch(addressServiceProvider)
      .getAddresses(userId);
  try {
    return addresses.firstWhere((a) => a.isDefault);
  } catch (_) {
    return addresses.isNotEmpty ? addresses.first : null;
  }
});

/// The address selected during checkout (null = use profile address)
final selectedAddressProvider = StateProvider<UserAddress?>((ref) => null);
