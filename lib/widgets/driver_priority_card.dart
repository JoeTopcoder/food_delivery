import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/driver_priority_provider.dart';
import '../screens/driver/driver_priority_screen.dart';

/// Compact standing chip for the driver dashboard's duty card — emoji, label
/// and score in a small pill; taps through to the full performance page.
class DriverStandingChip extends ConsumerWidget {
  const DriverStandingChip({super.key, required this.driverId});

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(driverPriorityProvider(driverId)).valueOrNull;
    if (p == null) return const SizedBox.shrink();
    final color = standingColor(p.standing);
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverPriorityScreen(driverId: driverId),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(p.standing.emoji, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                p.standing.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w800, color: color),
              ),
            ),
            const SizedBox(width: 4),
            Text(p.score.toStringAsFixed(0),
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    color: Colors.white)),
          ],
        ),
      ),
    );
  }
}

Color standingColor(DriverStanding s) => switch (s) {
      DriverStanding.elite => const Color(0xFF7C3AED),
      DriverStanding.priority => const Color(0xFFFF5A1F),
      DriverStanding.goodStanding => const Color(0xFF2563EB),
      DriverStanding.standard => const Color(0xFFF59E0B),
      DriverStanding.needsImprovement => const Color(0xFFDC2626),
    };

/// 🔥 MY HOTBITE PRIORITY — the driver-dashboard summary card. Shows standing,
/// score, a progress bar toward the next level, and a single concrete
/// improvement hint. All values come from the trusted backend RPC.
class DriverPriorityCard extends ConsumerWidget {
  const DriverPriorityCard({super.key, required this.driverId});

  final String driverId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(driverPriorityProvider(driverId));
    final p = async.valueOrNull;
    if (p == null) return const SizedBox.shrink();

    final color = standingColor(p.standing);
    final pct = (p.score / 100).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DriverPriorityScreen(driverId: driverId),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.04)],
          ),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                const Text('MY HOTBITE PRIORITY',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4)),
                const Spacer(),
                Icon(Icons.chevron_right_rounded,
                    color: color.withValues(alpha: 0.8)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(p.standing.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 8),
                Text(p.standing.label,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: color)),
                const Spacer(),
                Text(p.score.toStringAsFixed(0),
                    style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w900)),
                const Padding(
                  padding: EdgeInsets.only(bottom: 3),
                  child: Text(' / 100',
                      style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.15),
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              p.provisional
                  ? 'Your score is provisional until you complete 10 deliveries.'
                  : p.nextStanding == null
                      ? "You're receiving priority access to eligible orders."
                      : '${p.pointsToNext.toStringAsFixed(0)} points to '
                          '${DriverStanding.parse(p.nextStanding).label}.',
              style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(alpha: 0.7)),
            ),
          ],
        ),
      ),
    );
  }
}
