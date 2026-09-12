import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../config/app_constants.dart';
import '../../config/supabase_config.dart';
import '../../providers/user_provider.dart';

/// Whether we can actually deliver to where this customer is.
class Coverage {
  const Coverage({required this.nearestKm, required this.maxKm});

  /// Distance to the closest store, or null when it could not be measured —
  /// no catalogue, or the lookup failed.
  final double? nearestKm;
  final double maxKm;

  /// Only true when we are certain. An unmeasurable answer is treated as
  /// covered, because showing "we don't deliver here" to someone we simply
  /// failed to measure is far worse than showing them an ordinary empty list.
  bool get isOutOfArea => nearestKm != null && nearestKm! > maxKm;

  /// How far past the edge they are, for wording like "35 km away".
  double? get nearestKmRounded =>
      nearestKm == null ? null : (nearestKm! * 10).round() / 10;
}

final coverageProvider = FutureProvider.autoDispose<Coverage>((ref) async {
  final service = ref.watch(restaurantServiceProvider);
  final nearest = await service.nearestStoreKm();
  return Coverage(nearestKm: nearest, maxKm: AppConstants.browseMaxKm);
});

/// Records that someone wants delivery somewhere we do not reach yet.
///
/// The write goes through join_coverage_waitlist rather than the table, so the
/// account is taken from the session and the list cannot be read back by the
/// people on it.
class CoverageService {
  CoverageService(this._client);
  final SupabaseClient _client;

  Future<void> joinWaitlist({
    required String contact,
    double? latitude,
    double? longitude,
    String? address,
    double? nearestKm,
  }) async {
    await _client.rpc(
      'join_coverage_waitlist',
      params: {
        'p_contact': contact.trim(),
        'p_latitude': latitude,
        'p_longitude': longitude,
        'p_address': address,
        'p_nearest_km': nearestKm,
      },
    );
  }
}

final coverageServiceProvider = Provider<CoverageService>(
  (ref) => CoverageService(SupabaseConfig.client),
);
