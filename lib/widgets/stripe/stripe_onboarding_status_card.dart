import 'package:flutter/material.dart';
import '../../models/stripe/connected_account_model.dart';

/// Card summarising the Stripe Connect onboarding state with contextual
/// colour, icon, title and subtitle. Optionally shows an action button.
class StripeOnboardingStatusCard extends StatelessWidget {
  const StripeOnboardingStatusCard({
    super.key,
    required this.account,
    this.onFix,
  });

  final ConnectedAccount account;

  /// Called when the user taps the action button (Fix / Continue Setup).
  final VoidCallback? onFix;

  @override
  Widget build(BuildContext context) {
    if (account.isComplete) {
      return _card(
        const Color(0xFF22C55E),
        Icons.check_circle_outline,
        'Payouts Active',
        'Your Stripe account is set up and ready to receive payouts.',
      );
    }

    if (account.isRestricted) {
      final subtitle = account.requirementsCurrentlyDue.isNotEmpty
          ? 'Missing: ${account.requirementsCurrentlyDue.take(3).join(', ')}'
          : (account.disabledReason ?? 'Your account has restrictions.');
      return _card(
        const Color(0xFFEF4444),
        Icons.warning_amber_rounded,
        'Action Required',
        subtitle,
        action: onFix != null
            ? TextButton(
                onPressed: onFix,
                child: const Text(
                  'Fix Account',
                  style: TextStyle(color: Color(0xFFEF4444)),
                ),
              )
            : null,
      );
    }

    // Pending / not_started
    return _card(
      const Color(0xFFF59E0B),
      Icons.hourglass_top_rounded,
      'Setup Incomplete',
      'Complete Stripe onboarding to receive payouts.',
      action: onFix != null
          ? TextButton(
              onPressed: onFix,
              child: const Text(
                'Continue Setup',
                style: TextStyle(color: Color(0xFFF59E0B)),
              ),
            )
          : null,
    );
  }

  Widget _card(
    Color color,
    IconData icon,
    String title,
    String subtitle, {
    Widget? action,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
          if (action != null) ...[
            const SizedBox(width: 8),
            action,
          ],
        ],
      ),
    );
  }
}
