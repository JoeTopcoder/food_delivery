import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/host_rewards/host_rewards_service.dart';

final hostRewardsServiceProvider =
    Provider<HostRewardsService>((ref) => HostRewardsService());

final hostRewardsOverviewProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(hostRewardsServiceProvider).overview();
});

final hostsListProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(hostRewardsServiceProvider).hosts();
});

final hostPropertiesProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, hostId) async {
  return ref.watch(hostRewardsServiceProvider).properties(hostId: hostId);
});

final hostCommissionsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String?>((ref, status) async {
  return ref.watch(hostRewardsServiceProvider).commissions(status: status);
});

final hostPayoutsProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(hostRewardsServiceProvider).payouts();
});

final hostRewardsConfigProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  return ref.watch(hostRewardsServiceProvider).config();
});
