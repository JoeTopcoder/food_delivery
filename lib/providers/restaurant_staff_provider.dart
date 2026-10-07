import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
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

/// True when the signed-in user has a pending staff invitation addressed to
/// their email. Lets the customer profile show "Accept staff invite" only to
/// people who were actually invited — regular customers never see it, and the
/// (only) manual accept path is still available to real invitees.
final hasPendingStaffInviteProvider =
    FutureProvider.autoDispose<bool>((ref) async {
  final userId = ref.watch(currentUserIdProvider);
  if (userId == null) return false;
  try {
    final res = await SupabaseConfig.client.rpc('staff_has_pending_invite');
    return res == true;
  } catch (_) {
    return false;
  }
});
