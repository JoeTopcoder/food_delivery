import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/stripe/payout_request_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/stripe/earnings_provider.dart';
import '../../providers/stripe/connected_account_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/stripe/earnings_balance_card.dart';
import '../../widgets/stripe/payout_status_badge.dart';
import '../../widgets/stripe/money_text.dart';
import '../../widgets/stripe/stripe_onboarding_status_card.dart';
import 'payout_setup_screen.dart';
import 'request_payout_sheet.dart';

class EarningsDashboardScreen extends ConsumerWidget {
  final String role;
  const EarningsDashboardScreen({super.key, required this.role});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider) ?? '';
    final earningsState = ref.watch(earningsProvider(role));
    final accountState = ref.watch(connectedAccountProvider(userId));
    final account = accountState.account;
    final summary = earningsState.summary;
    final settings = earningsState.settings;
    final isOnboarded = account?.isComplete ?? false;
    final canRequest = isOnboarded &&
        settings != null &&
        summary.availableBalanceCents >= settings.minPayoutCents;

    final bool needsSetup = !isOnboarded;
    String buttonLabel;
    if (canRequest) {
      buttonLabel = 'Request Payout';
    } else if (needsSetup) {
      buttonLabel = 'Set Up Payout Account';
    } else {
      final minStr =
          '\$${((settings?.minPayoutCents ?? 1000) / 100).toStringAsFixed(2)}';
      buttonLabel = 'Minimum $minStr Required';
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        title: const Text('My Earnings'),
        backgroundColor: const Color(0xFF0F1117),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () =>
                ref.read(earningsProvider(role).notifier).load(),
          ),
        ],
      ),
      body: earningsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(earningsProvider(role).notifier).load(),
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Balance card
                  EarningsBalanceCard(summary: summary),
                  const SizedBox(height: 20),

                  // Onboarding / setup banner
                  if (!isOnboarded) ...[
                    if (account != null)
                      StripeOnboardingStatusCard(
                        account: account,
                        onFix: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                PayoutSetupScreen(role: role),
                          ),
                        ),
                      )
                    else
                      _setupBanner(context, role),
                    const SizedBox(height: 20),
                  ],

                  // Request payout button
                  Builder(builder: (context) {
                    final s = settings;

                    VoidCallback? onPressed;
                    if (canRequest && s != null) {
                      onPressed = () => _showRequestSheet(
                            context,
                            ref,
                            s.minPayoutCents,
                            s.maxPayoutCents,
                            summary.availableBalanceCents,
                          );
                    } else if (needsSetup) {
                      onPressed = () => _promptSetup(context);
                    }
                    // belowMin → button stays disabled (null)

                    final btnColor = needsSetup
                        ? const Color(0xFF7C3AED)
                        : AppTheme.primaryColor;

                    return SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: onPressed,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: btnColor,
                          disabledBackgroundColor: Colors.white12,
                          padding:
                              const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (needsSetup) ...[
                              const Icon(Icons.account_balance_wallet,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              buttonLabel,
                              style: TextStyle(
                                color: onPressed != null
                                    ? Colors.white
                                    : Colors.white38,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 28),

                  // Payout history
                  const Text(
                    'Payout History',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (earningsState.recentPayouts.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Text(
                          'No payouts yet',
                          style: TextStyle(
                              color: Colors.white38, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    ...earningsState.recentPayouts
                        .map((p) => _payoutTile(p)),
                ],
              ),
            ),
    );
  }

  void _promptSetup(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1D2E),
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.account_balance_wallet,
                  color: Color(0xFF7C3AED), size: 36),
            ),
            const SizedBox(height: 20),
            const Text(
              'Payout Account Required',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'You need to connect a bank account through Stripe before you can request a payout. It only takes a few minutes.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white60, fontSize: 14, height: 1.5),
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PayoutSetupScreen(role: role),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF7C3AED),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Set Up Payout Account',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Maybe Later',
                  style: TextStyle(color: Colors.white38)),
            ),
          ],
        ),
      ),
    );
  }

  void _showRequestSheet(
    BuildContext context,
    WidgetRef ref,
    int min,
    int max,
    int available,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RequestPayoutSheet(
        role: role,
        minCents: min,
        maxCents: max,
        availableCents: available,
      ),
    ).then((_) => ref.read(earningsProvider(role).notifier).load());
  }

  Widget _setupBanner(BuildContext context, String role) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF7C3AED).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_balance_wallet_outlined,
            color: Color(0xFF7C3AED),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Set up Stripe to receive payouts',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => PayoutSetupScreen(role: role),
              ),
            ),
            child: const Text('Set Up'),
          ),
        ],
      ),
    );
  }

  Widget _payoutTile(PayoutRequest p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MoneyText(
                  p.amountCents,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${p.createdAt.day}/${p.createdAt.month}/${p.createdAt.year}',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
                if (p.failureMessage != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    p.failureMessage!,
                    style: const TextStyle(
                      color: Color(0xFFEF4444),
                      fontSize: 11,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          PayoutStatusBadge(p.status),
        ],
      ),
    );
  }
}
