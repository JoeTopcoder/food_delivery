import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/supabase_config.dart';
import '../../models/catalog/menu_model.dart';
import '../auth_user/auth_provider.dart';
import '../platform/feature_providers.dart';

/// Returns a copy of [raw] whose CHARGED price (discountedPrice) is the HotBite+
/// member price for active members, while keeping the regular price on `price`
/// so the cart/checkout can show the saving. Non-members get [raw] unchanged.
/// Used everywhere an item is added to a cart so display and charge always match.
MenuItem memberPricedItem(MenuItem raw, bool isMember) {
  if (!isMember || !raw.hasMemberPrice) return raw;
  final regular = raw.discountedPrice; // non-member price
  final pct = ((1 - raw.memberPrice / regular) * 100).clamp(0.0, 100.0);
  return raw.copyWith(price: regular, discount: pct);
}

/// A HotBite+ membership plan (admin-priced, from the DB).
class MembershipPlan {
  final String id;
  final String name;
  final String? description;
  final double price;
  final int durationDays;
  final bool isRecommended;

  const MembershipPlan({
    required this.id,
    required this.name,
    this.description,
    required this.price,
    required this.durationDays,
    required this.isRecommended,
  });

  factory MembershipPlan.fromJson(Map<String, dynamic> j) => MembershipPlan(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Plan',
        description: j['description'] as String?,
        price: ((j['price'] as num?) ?? 0).toDouble(),
        durationDays: (j['duration_days'] as num?)?.toInt() ?? 30,
        isRecommended: (j['is_recommended'] as bool?) ?? false,
      );
}

/// The customer's current HotBite+ membership snapshot (from the trusted
/// `get_active_membership` RPC). `isActive` is the only source of truth for
/// whether member benefits apply.
class MembershipStatus {
  final bool isActive;
  final String? planName;
  final DateTime? endDate;
  final String? status;
  final bool autoRenew;

  const MembershipStatus({
    required this.isActive,
    this.planName,
    this.endDate,
    this.status,
    this.autoRenew = false,
  });

  static const none = MembershipStatus(isActive: false);

  factory MembershipStatus.fromJson(Map<String, dynamic> j) => MembershipStatus(
        isActive: (j['is_active'] as bool?) ?? false,
        planName: j['plan_name'] as String?,
        endDate: j['end_date'] != null
            ? DateTime.tryParse(j['end_date'].toString())
            : null,
        status: j['status'] as String?,
        autoRenew: (j['auto_renew'] as bool?) ?? false,
      );
}

/// Whether HotBite+ is switched on at all (admin feature flag).
final hotbitePlusEnabledProvider = Provider<bool>((ref) {
  ref.watch(configVersionProvider);
  final rows = ref.watch(_configFlagsProvider).valueOrNull ?? const {};
  return rows['hotbite_plus_enabled'] ?? false;
});

final _configFlagsProvider =
    FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  ref.watch(configVersionProvider);
  try {
    final rows = await SupabaseConfig.client
        .from('app_config')
        .select('key, value')
        .like('key', '%hotbite_plus%');
    final m = <String, bool>{};
    for (final r in (rows as List)) {
      m[r['key'] as String] = r['value'] == 'true' || r['value'] == '1';
    }
    return m;
  } catch (_) {
    return const {};
  }
});

/// The customer's membership status. Re-fetches (and the RPC re-evaluates
/// expiry) each time it's watched fresh.
final membershipStatusProvider =
    FutureProvider.autoDispose<MembershipStatus>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return MembershipStatus.none;
  try {
    final res = await SupabaseConfig.client
        .rpc('get_active_membership', params: {'p_user_id': uid});
    if (res == null) return MembershipStatus.none;
    return MembershipStatus.fromJson(Map<String, dynamic>.from(res as Map));
  } catch (_) {
    return MembershipStatus.none;
  }
});

/// Convenience: is the current customer an active HotBite+ member?
final isHotBitePlusMemberProvider = Provider.autoDispose<bool>((ref) {
  return ref.watch(membershipStatusProvider).valueOrNull?.isActive ?? false;
});

/// Available (active) membership plans, ordered.
final membershipPlansProvider =
    FutureProvider.autoDispose<List<MembershipPlan>>((ref) async {
  try {
    final rows = await SupabaseConfig.client
        .from('membership_plans')
        .select()
        .eq('is_active', true)
        .order('display_order');
    return (rows as List)
        .map((e) => MembershipPlan.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  } catch (_) {
    return const [];
  }
});
