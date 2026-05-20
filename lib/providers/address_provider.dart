import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/address_model.dart';
import '../services/address_service.dart';
import 'auth_provider.dart';

final addressServiceProvider = Provider<AddressService>((ref) {
  return AddressService(Supabase.instance.client);
});

final userAddressesProvider = FutureProvider.autoDispose.family<List<UserAddress>, String>((
  ref,
  userId,
) {
  final service = ref.watch(addressServiceProvider);

  // Subscribe to real-time changes on user_addresses for this user
  final channel = Supabase.instance.client.realtime.channel(
    'addr_$userId',
  );
  channel
      .onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'user_addresses',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'user_id',
          value: userId,
        ),
        callback: (_) {
          ref.invalidateSelf();
        },
      )
      .subscribe();

  // Clean up the channel when the provider is disposed
  ref.onDispose(() {
    Supabase.instance.client.realtime.removeChannel(channel);
  });

  return service.getAddresses(userId);
});

/// The default address for a given user (first where is_default == true).
final defaultAddressProvider = FutureProvider.autoDispose.family<UserAddress?, String>((
  ref,
  userId,
) async {
  // This depends on userAddressesProvider, so it auto-refreshes with realtime
  final addresses = await ref.watch(userAddressesProvider(userId).future);
  try {
    return addresses.firstWhere((a) => a.isDefault);
  } catch (_) {
    return addresses.isNotEmpty ? addresses.first : null;
  }
});

/// The address selected during checkout (null = use profile address)
/// Stores only the ID — the actual address is derived reactively from
/// [userAddressesProvider] so edits propagate everywhere in real-time.
final selectedAddressIdProvider = StateProvider<String?>((ref) => null);

/// Derives the full [UserAddress] from the latest address list + selected ID.
/// Falls back to default address when nothing is explicitly selected.
final selectedAddressProvider = Provider<UserAddress?>((ref) {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return null;

  final selectedId = ref.watch(selectedAddressIdProvider);
  final addressAsync = ref.watch(userAddressesProvider(userId));

  return addressAsync.whenOrNull(
    data: (addresses) {
      if (addresses.isEmpty) return null;
      if (selectedId != null) {
        final match = addresses.where((a) => a.id == selectedId);
        if (match.isNotEmpty) return match.first;
      }
      // Nothing selected — pick default or first
      final defaults = addresses.where((a) => a.isDefault);
      return defaults.isNotEmpty ? defaults.first : addresses.first;
    },
  );
});
