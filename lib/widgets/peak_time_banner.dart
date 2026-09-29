import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/peak_time_provider.dart';
import '../config/app_constants.dart';

/// Customer-facing Peak Time indicator. Renders nothing unless Peak Time is
/// currently ON, so it adds no clutter during normal volume. Shown on browsing
/// and checkout via the shared authoritative [peakTimeProvider].
class PeakTimeBanner extends ConsumerWidget {
  /// When true (checkout), also shows the applicable surcharge line if a fee
  /// applies. Elsewhere (browsing) only the "high volume" notice is shown.
  final bool showFee;

  /// Driver-facing wording instead of the customer copy.
  final bool driver;
  final EdgeInsetsGeometry margin;

  const PeakTimeBanner({
    super.key,
    this.showFee = false,
    this.driver = false,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peak = ref.watch(peakTimeStateProvider);
    if (!peak.isPeakTime) return const SizedBox.shrink();

    final fee = peak.applicableFee;
    return Container(
      margin: margin,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.local_fire_department_rounded,
              color: Color(0xFFF59E0B), size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  driver ? 'Peak Time — High Order Volume' : 'Peak Time',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    color: Color(0xFFB45309),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  driver
                      ? 'Lots of orders are coming in right now.'
                      : 'High order volume right now. Delivery times may be slightly longer.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.brown.shade700,
                  ),
                ),
                if (showFee && fee > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    'A Peak Time fee of ${AppConstants.currencySymbol}${fee.toStringAsFixed(2)} applies to this order.',
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB45309),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
