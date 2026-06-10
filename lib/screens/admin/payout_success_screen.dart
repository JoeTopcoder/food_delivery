import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';

/// Full-screen success confirmation after a Stripe payout completes.
class PayoutSuccessScreen extends StatelessWidget {
  final Map<String, dynamic> result;

  const PayoutSuccessScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final amount = (result['amount'] as num?)?.toDouble() ?? 0;
    final recipient = result['recipient_name'] as String? ?? 'N/A';
    final bankName = result['bank_name'] as String? ?? '';
    final bankAccount = result['bank_account'] as String? ?? '';
    final payoutRef = result['payout_reference'] as String? ?? '';
    final payoutId = result['payout_id'] as String? ?? '';
    final requesterType = result['requester_type'] as String? ?? '';
    final fmt = NumberFormat('#,##0.00');
    final now = DateFormat('MMM d, yyyy · h:mm a').format(DateTime.now());
    final maskedAccount = bankAccount.length > 4
        ? '${'•' * (bankAccount.length - 4)}${bankAccount.substring(bankAccount.length - 4)}'
        : bankAccount;

    return Scaffold(
      backgroundColor: const Color(0xFFF0FDF4),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: MediaQuery.of(context).size.height -
                  MediaQuery.of(context).padding.top -
                  MediaQuery.of(context).padding.bottom,
            ),
            child: IntrinsicHeight(
              child: Column(
                children: [
            // ── Top space + animated check ─────────────────────
            const Spacer(flex: 2),
            const _AnimatedCheck(),
            const SizedBox(height: 24),
            const Text(
              'Payment Sent!',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Color(0xFF166534),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'The payout has been processed via Stripe',
              style: TextStyle(
                fontSize: 14,
                color: const Color(0xFF166534).withValues(alpha: 0.7),
              ),
            ),
            const Spacer(),

            // ── Receipt card ──────────────────────────────────
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  // Amount
                  Text(
                    '${AppConstants.currencySymbol}${fmt.format(amount)}',
                    style: const TextStyle(
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF22C55E).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'COMPLETED',
                      style: TextStyle(
                        color: Color(0xFF22C55E),
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Divider
                  Row(
                    children: List.generate(
                      40,
                      (_) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          height: 1,
                          color: Colors.grey.shade200,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Details
                  _row('Recipient', recipient),
                  if (requesterType.isNotEmpty)
                    _row(
                      'Type',
                      requesterType == 'driver'
                          ? '🚗 Driver'
                          : '🍽️ Restaurant',
                    ),
                  if (bankName.isNotEmpty) _row('Bank', bankName),
                  if (maskedAccount.isNotEmpty) _row('Account', maskedAccount),
                  _row('Date', now),

                  const SizedBox(height: 16),
                  Row(
                    children: List.generate(
                      40,
                      (_) => Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 1.5),
                          height: 1,
                          color: Colors.grey.shade200,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Reference IDs
                  if (payoutRef.isNotEmpty)
                    _row(
                      'Stripe Ref',
                      payoutRef.length > 20
                          ? '${payoutRef.substring(0, 20)}…'
                          : payoutRef,
                    ),
                  if (payoutId.isNotEmpty)
                    _row(
                      'Payout ID',
                      payoutId.length > 12
                          ? '${payoutId.substring(0, 12)}…'
                          : payoutId,
                    ),
                ],
              ),
            ),
            const Spacer(),

            // ── Done button ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Done',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Animated checkmark ────────────────────────────────────────────────

class _AnimatedCheck extends StatefulWidget {
  const _AnimatedCheck();

  @override
  State<_AnimatedCheck> createState() => _AnimatedCheckState();
}

class _AnimatedCheckState extends State<_AnimatedCheck>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _scale = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          width: 100,
          height: 100,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xFF22C55E),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF22C55E).withValues(alpha: 0.3),
                blurRadius: 30,
                spreadRadius: 5,
              ),
            ],
          ),
          child: const Icon(Icons.check_rounded, color: Colors.white, size: 52),
        ),
      ),
    );
  }
}
