import 'package:flutter/material.dart';
import '../config/app_constants.dart';
import '../services/delivery_fee_service.dart';

/// A compact card that shows how the delivery fee was calculated.
///
/// Supply a [DeliveryFeeResult] (from [DeliveryFeeService.calculate]) and
/// optionally a [driverTip].  The widget renders:
///   • Base fee
///   • Distance charge (if distance-based)
///   • Surge premium (if active)
///   • Minimum-fee notice (when min_fee kicked in)
///   • Total delivery fee
///   • Driver pay / platform split (admin-only, controlled by [showDriverSplit])
class DeliveryFeeBreakdown extends StatelessWidget {
  final DeliveryFeeResult result;
  final double driverTip;

  /// If true, show driver-pay / platform-fee split. Hide for customers.
  final bool showDriverSplit;

  const DeliveryFeeBreakdown({
    super.key,
    required this.result,
    this.driverTip = 0,
    this.showDriverSplit = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sym = AppConstants.currencySymbol;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withAlpha(80)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ────────────────────────────────────────────────────
          Row(
            children: [
              Icon(Icons.local_shipping_outlined, size: 18, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                'Delivery Fee Breakdown',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              if (result.distanceKm != null)
                _badge(context, result.distanceLabel),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),

          // ── Line items ────────────────────────────────────────────────
          if (result.calculation == 'distance_based') ...[
            _row(
              'Base fee (first ${result.baseKm?.toStringAsFixed(0) ?? '—'} mi)',
              '$sym${result.baseFee?.toStringAsFixed(2) ?? '—'}',
            ),
            if ((result.extraKm ?? 0) > 0)
              _row(
                'Distance (${result.extraKm?.toStringAsFixed(1)} mi × $sym${result.perKmFee?.toStringAsFixed(2)}/mi)',
                '$sym${((result.extraKm ?? 0) * (result.perKmFee ?? 0)).toStringAsFixed(2)}',
              ),
          ] else ...[
            _row(
              'Flat delivery fee',
              '$sym${result.deliveryFee.toStringAsFixed(2)}',
            ),
          ],

          if (result.hasSurge)
            _row(
              'Surge (×${result.surgeMultiplier.toStringAsFixed(1)})',
              'included',
              valueColor: Colors.orange.shade700,
            ),

          if (result.minFee != null && result.deliveryFee <= result.minFee!)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Minimum fee of $sym${result.minFee!.toStringAsFixed(2)} applied',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.outline,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),

          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 8),

          // ── Total ─────────────────────────────────────────────────────
          _row(
            'Delivery Fee',
            '$sym${result.deliveryFee.toStringAsFixed(2)}',
            bold: true,
          ),

          if (driverTip > 0) ...[
            const SizedBox(height: 4),
            _row('Driver Tip', '$sym${driverTip.toStringAsFixed(2)}'),
          ],

          // ── Driver / Platform split (admin view) ──────────────────────
          if (showDriverSplit) ...[
            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),
            _row(
              'Driver pay (${(result.driverPayPercent * 100).toStringAsFixed(0)}%)',
              '$sym${result.driverPay.toStringAsFixed(2)}',
              valueColor: Colors.green.shade700,
            ),
            _row(
              'Platform fee',
              '$sym${result.platformFee.toStringAsFixed(2)}',
              valueColor: cs.outline,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(
    String label,
    String value, {
    bool bold = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w600 : FontWeight.w400,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(BuildContext context, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}
