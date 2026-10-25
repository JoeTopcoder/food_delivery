import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/host_rewards/host_portal_service.dart';

final hostPortalServiceProvider =
    Provider<HostPortalService>((ref) => HostPortalService());

final hostDashboardProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(hostPortalServiceProvider).dashboard();
});

final hostMyPropertiesProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(hostPortalServiceProvider).myProperties();
});

final hostMyCommissionsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(hostPortalServiceProvider).myCommissions();
});

final hostMyPayoutsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(hostPortalServiceProvider).myPayouts();
});
