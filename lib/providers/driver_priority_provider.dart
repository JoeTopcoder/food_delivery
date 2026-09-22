import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';

/// The five HotBite driver standings, in ascending order.
enum DriverStanding {
  needsImprovement,
  standard,
  goodStanding,
  priority,
  elite;

  static DriverStanding parse(String? s) {
    switch (s) {
      case 'ELITE':
        return DriverStanding.elite;
      case 'PRIORITY':
        return DriverStanding.priority;
      case 'GOOD_STANDING':
        return DriverStanding.goodStanding;
      case 'STANDARD':
        return DriverStanding.standard;
      default:
        return DriverStanding.needsImprovement;
    }
  }

  String get label => switch (this) {
        DriverStanding.elite => 'Elite',
        DriverStanding.priority => 'Priority',
        DriverStanding.goodStanding => 'Good Standing',
        DriverStanding.standard => 'Standard',
        DriverStanding.needsImprovement => 'Needs Improvement',
      };

  String get emoji => switch (this) {
        DriverStanding.elite => '🏆',
        DriverStanding.priority => '🥇',
        DriverStanding.goodStanding => '🥈',
        DriverStanding.standard => '🟡',
        DriverStanding.needsImprovement => '🔴',
      };
}

/// Trusted driver priority snapshot, computed and returned by the backend
/// `get_driver_priority` RPC. The client only displays it — it never computes
/// or stores the official score.
class DriverPriority {
  final double score; // 0–100
  final DriverStanding standing;
  final bool provisional;
  final String? nextStanding; // raw key of the next level up, or null at top
  final double pointsToNext;
  final String improveFactor; // e.g. "on-time delivery"
  final Map<String, dynamic> stats;

  const DriverPriority({
    required this.score,
    required this.standing,
    required this.provisional,
    required this.nextStanding,
    required this.pointsToNext,
    required this.improveFactor,
    required this.stats,
  });

  factory DriverPriority.fromJson(Map<String, dynamic> j) => DriverPriority(
        score: ((j['score'] as num?) ?? 0).toDouble(),
        standing: DriverStanding.parse(j['standing'] as String?),
        provisional: (j['provisional'] as bool?) ?? true,
        nextStanding: j['next_standing'] as String?,
        pointsToNext: ((j['points_to_next'] as num?) ?? 0).toDouble(),
        improveFactor: (j['improve_factor'] as String?) ?? 'on-time delivery',
        stats: (j['stats'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  double statNum(String k) => ((stats[k] as num?) ?? 0).toDouble();

  DriverStanding? get nextStandingParsed =>
      nextStanding == null ? null : DriverStanding.parse(nextStanding);
}

/// Fetches the driver's trusted priority snapshot. autoDispose so it refreshes
/// each time the dashboard opens; the RPC recomputes server-side.
final driverPriorityProvider = FutureProvider.autoDispose
    .family<DriverPriority?, String>((ref, driverId) async {
  try {
    final res = await SupabaseConfig.client
        .rpc('get_driver_priority', params: {'p_driver_id': driverId});
    if (res == null) return null;
    return DriverPriority.fromJson(Map<String, dynamic>.from(res as Map));
  } catch (_) {
    return null;
  }
});

/// The driver's priority audit history (standing changes / score moves).
final driverPriorityHistoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, driverId) async {
  try {
    final rows = await SupabaseConfig.client
        .from('driver_priority_events')
        .select('event_type, score_change, previous_score, new_score, reason, created_at')
        .eq('driver_id', driverId)
        .order('created_at', ascending: false)
        .limit(30);
    return (rows as List).cast<Map<String, dynamic>>();
  } catch (_) {
    return const [];
  }
});
