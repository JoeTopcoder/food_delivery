import 'package:flutter/material.dart';
import '../../models/stripe/earnings_summary_model.dart';
import 'money_text.dart';

/// Hero card showing the user's available balance and secondary stats
/// (pending, processing, lifetime) with a purple gradient background.
class EarningsBalanceCard extends StatelessWidget {
  const EarningsBalanceCard({super.key, required this.summary});
  final EarningsSummary summary;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF4F46E5).withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Available Balance',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 4),
          MoneyText(
            summary.availableBalanceCents,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _stat('Pending', summary.pendingBalanceCents),
              const SizedBox(width: 24),
              _stat('Processing', summary.lockedBalanceCents),
              const SizedBox(width: 24),
              _stat('Lifetime', summary.lifetimeEarnedCents),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, int cents) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
        MoneyText(
          cents,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
