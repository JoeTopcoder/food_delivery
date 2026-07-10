import 'package:flutter/material.dart';
import '../../models/stripe/payout_request_model.dart';

/// A compact colored badge displaying a PayoutStatus label.
class PayoutStatusBadge extends StatelessWidget {
  const PayoutStatusBadge(this.status, {super.key});
  final PayoutStatus status;

  Color get _color {
    switch (status) {
      case PayoutStatus.paid:
        return const Color(0xFF22C55E);
      case PayoutStatus.processing:
      case PayoutStatus.transferred:
        return const Color(0xFF3B82F6);
      case PayoutStatus.requested:
      case PayoutStatus.approved:
        return const Color(0xFFF59E0B);
      case PayoutStatus.failed:
        return const Color(0xFFEF4444);
      case PayoutStatus.canceled:
      case PayoutStatus.rejected:
        return const Color(0xFF6B7280);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.4)),
      ),
      child: Text(
        status.label,
        style: TextStyle(
          color: _color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
