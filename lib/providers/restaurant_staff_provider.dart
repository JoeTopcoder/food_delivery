import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/restaurant/staff_service.dart';
import 'auth_provider.dart';

final staffServiceProvider = Provider<StaffService>((ref) => StaffService());

/// True when the signed-in user is active staff of at least one restaurant.
/// Used to gate staff-only UI (e.g. the "My Shift" cashier reconciliation
/// entry) so regular customers don't see it. Rebuilds when the user changes.
final isRestaurantStaffProvider = FutureProvider.autoDispose<bool>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  try {
    final memberships = await ref.watch(staffServiceProvider).myMemberships();
    return memberships.isNotEmpty;
  } catch (_) {
    return false;
  }
});
