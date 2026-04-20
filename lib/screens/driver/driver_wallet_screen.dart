import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/driver_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/payout_service.dart'
    show StripePayoutService, PayoutRecord, StripePayoutException;
import '../../utils/friendly_error.dart';

// ── Providers ──────────────────────────────────────────────────────────────

final payoutHistoryProvider = FutureProvider.family<List<PayoutRecord>, String>(
  (ref, driverId) async {
    return StripePayoutService.instance.getPayoutHistory(driverId);
  },
);

// ── Screen ─────────────────────────────────────────────────────────────────

class DriverWalletScreen extends ConsumerStatefulWidget {
  const DriverWalletScreen({super.key});

  @override
  ConsumerState<DriverWalletScreen> createState() => _DriverWalletScreenState();
}

class _DriverWalletScreenState extends ConsumerState<DriverWalletScreen> {
  bool _connecting = false;
  bool _payingOut = false;
  String? _errorMessage;
  String? _successMessage;

  static const _bg = Color(0xFF0F1117);
  static const _card = Color(0xFF1C1F2E);
  static const _accent = Color(0xFF6C63FF);
  static const _green = Color(0xFF00C896);

  // ── Stripe onboarding ───────────────────────────────────────────────────

  Future<void> _startStripeOnboarding() async {
    setState(() {
      _connecting = true;
      _errorMessage = null;
    });
    try {
      final url = await StripePayoutService.instance.getStripeOnboardingUrl();
      if (!mounted) return;
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        setState(() => _errorMessage = 'Could not open Stripe onboarding.');
      }
    } catch (e) {
      setState(() => _errorMessage = friendlyError(e));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  // ── Cash out ────────────────────────────────────────────────────────────

  Future<void> _cashOut(Driver driver, double availableBalance) async {
    final amountUsd = availableBalance;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _CashOutDialog(amount: amountUsd),
    );
    if (confirmed != true) return;

    setState(() {
      _payingOut = true;
      _errorMessage = null;
      _successMessage = null;
    });

    try {
      late final Map<String, dynamic> result;
      try {
        result = await StripePayoutService.instance.requestPayout(
          amountCents: (amountUsd * 100).round(),
          payoutType: 'instant',
        );
      } on StripePayoutException catch (ex) {
        if (!mounted) return;
        if (ex.fallbackAvailable) {
          // Instant failed — offer standard
          final useStandard = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: _card,
              title: const Text(
                'Instant Payout Unavailable',
                style: TextStyle(color: Colors.white),
              ),
              content: Text(
                '${ex.message}\n\nWould you like a standard payout instead? (2-5 business days)',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _accent),
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Standard Payout'),
                ),
              ],
            ),
          );
          if (useStandard == true) {
            await _requestStandardPayout(amountUsd);
          }
          return;
        }
        rethrow;
      }

      setState(
        () => _successMessage =
            'Payout of \$${amountUsd.toStringAsFixed(2)} initiated successfully!',
      );
      ref.invalidate(payoutHistoryProvider);
    } catch (e) {
      setState(() => _errorMessage = friendlyError(e));
    } finally {
      if (mounted) setState(() => _payingOut = false);
    }
  }

  Future<void> _requestStandardPayout(double amountUsd) async {
    try {
      await StripePayoutService.instance.requestPayout(
        amountCents: (amountUsd * 100).round(),
        payoutType: 'standard',
      );
      setState(
        () => _successMessage =
            'Standard payout of \$${amountUsd.toStringAsFixed(2)} requested. Funds arrive in 2-5 business days.',
      );
      ref.invalidate(payoutHistoryProvider);
    } catch (e) {
      setState(() => _errorMessage = friendlyError(e));
    }
  }

  // ── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(currentUserIdProvider);
    if (currentUserId == null) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Text('Not signed in', style: TextStyle(color: Colors.white)),
        ),
      );
    }

    final driverAsync = ref.watch(driverProfileProvider(currentUserId));
    final driver = driverAsync.valueOrNull;

    if (driver == null && driverAsync.isLoading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (driver == null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: Text(
            driverAsync.error?.toString() ?? 'Driver not found',
            style: const TextStyle(color: Colors.white70),
          ),
        ),
      );
    }

    final totalEarned = driver.totalEarnings ?? 0.0;
    final totalPaidOut = driver.totalPaidOut ?? 0.0;
    final available = (totalEarned - totalPaidOut).clamp(0.0, double.infinity);

    final payoutsAsync = ref.watch(payoutHistoryProvider(driver.id));

    return Scaffold(
      backgroundColor: _bg,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(driverProfileProvider);
          ref.invalidate(payoutHistoryProvider);
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ─ App Bar ─
            SliverAppBar(
              expandedHeight: 0,
              floating: true,
              backgroundColor: _bg,
              foregroundColor: Colors.white,
              title: const Text(
                'My Wallet',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),

            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ─ Balance card ─
                  _BalanceCard(
                    available: available,
                    totalEarned: totalEarned,
                    totalPaidOut: totalPaidOut,
                  ),

                  const SizedBox(height: 20),

                  // ─ Status / feedback messages ─
                  if (_successMessage != null)
                    _Banner(
                      message: _successMessage!,
                      color: _green,
                      icon: Icons.check_circle,
                    ),
                  if (_errorMessage != null)
                    _Banner(
                      message: _errorMessage!,
                      color: Colors.redAccent,
                      icon: Icons.error_outline,
                    ),

                  const SizedBox(height: 8),

                  // ─ Stripe connection status ─
                  _StripeStatusCard(
                    driver: driver,
                    connecting: _connecting,
                    onConnect: _startStripeOnboarding,
                  ),

                  const SizedBox(height: 20),

                  // ─ Cash Out button ─
                  _CashOutButton(
                    driver: driver,
                    available: available,
                    loading: _payingOut,
                    onTap: available > 0
                        ? () => _cashOut(driver, available)
                        : null,
                  ),

                  const SizedBox(height: 24),

                  // ─ Payout history ─
                  const Text(
                    'Payout History',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),

                  payoutsAsync.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Text(
                      friendlyError(e),
                      style: const TextStyle(color: Colors.white54),
                    ),
                    data: (payouts) => payouts.isEmpty
                        ? const _EmptyPayouts()
                        : Column(
                            children: payouts
                                .map((p) => _PayoutTile(payout: p))
                                .toList(),
                          ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final double available;
  final double totalEarned;
  final double totalPaidOut;

  const _BalanceCard({
    required this.available,
    required this.totalEarned,
    required this.totalPaidOut,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '\$');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C63FF), Color(0xFF3D5AFE)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6C63FF).withOpacity(0.35),
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
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            fmt.format(available),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              _BalanceStat(
                label: 'Total Earned',
                value: fmt.format(totalEarned),
              ),
              const SizedBox(width: 24),
              _BalanceStat(label: 'Paid Out', value: fmt.format(totalPaidOut)),
            ],
          ),
        ],
      ),
    );
  }
}

class _BalanceStat extends StatelessWidget {
  final String label;
  final String value;

  const _BalanceStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 11),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _StripeStatusCard extends StatelessWidget {
  final Driver driver;
  final bool connecting;
  final VoidCallback onConnect;

  const _StripeStatusCard({
    required this.driver,
    required this.connecting,
    required this.onConnect,
  });

  static const _card = Color(0xFF1C1F2E);

  @override
  Widget build(BuildContext context) {
    final status = driver.stripeAccountStatus ?? 'not_connected';
    final hasAccount = driver.stripeAccountId != null;

    Color statusColor;
    String statusText;
    switch (status) {
      case 'active':
        statusColor = const Color(0xFF00C896);
        statusText = 'Verified & Active';
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusText = 'Verification Pending';
        break;
      case 'restricted':
        statusColor = Colors.redAccent;
        statusText = 'Action Required';
        break;
      default:
        statusColor = Colors.white38;
        statusText = 'Not Connected';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: Color(0xFF6C63FF),
                size: 20,
              ),
              const SizedBox(width: 10),
              const Text(
                'Stripe Payout Account',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontSize: 11),
                ),
              ),
            ],
          ),
          if (status == 'active') ...[
            const SizedBox(height: 12),
            _CheckRow(label: 'KYC Verified', ok: driver.payoutsEnabled),
            const SizedBox(height: 4),
            _CheckRow(
              label: 'Debit card added (instant payouts)',
              ok: driver.stripeDebitCardAdded,
              warningIfFalse: 'Add a debit card to enable instant payouts',
            ),
          ],
          if (!hasAccount || status != 'active') ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: connecting ? null : onConnect,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6C63FF),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                icon: connecting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.open_in_new, size: 18),
                label: Text(
                  hasAccount ? 'Continue Stripe Setup' : 'Connect with Stripe',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool ok;
  final String? warningIfFalse;

  const _CheckRow({required this.label, required this.ok, this.warningIfFalse});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          ok ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 16,
          color: ok ? const Color(0xFF00C896) : Colors.white38,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: ok ? Colors.white70 : Colors.white38,
                  fontSize: 13,
                ),
              ),
              if (!ok && warningIfFalse != null)
                Text(
                  warningIfFalse!,
                  style: const TextStyle(color: Colors.orange, fontSize: 11),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _CashOutButton extends StatelessWidget {
  final Driver driver;
  final double available;
  final bool loading;
  final VoidCallback? onTap;

  const _CashOutButton({
    required this.driver,
    required this.available,
    required this.loading,
    this.onTap,
  });

  bool get _canInstant => driver.payoutsEnabled && driver.stripeDebitCardAdded;

  String get _disabledReason {
    if (driver.stripeAccountId == null ||
        (driver.stripeAccountStatus ?? '') == 'not_connected') {
      return 'Connect your Stripe account to cash out';
    }
    if (!driver.payoutsEnabled) {
      return 'Complete KYC verification in Stripe to enable payouts';
    }
    if (!driver.stripeDebitCardAdded) {
      return 'Add a debit card to enable instant payouts';
    }
    if (available <= 0) {
      return 'No available balance to cash out';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && _canInstant && available > 0;
    final fmt = NumberFormat.currency(symbol: '\$');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    colors: [Color(0xFF00C896), Color(0xFF00A876)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: enabled ? null : const Color(0xFF2A2D3E),
            borderRadius: BorderRadius.circular(14),
            boxShadow: enabled
                ? [
                    BoxShadow(
                      color: const Color(0xFF00C896).withOpacity(0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: enabled ? onTap : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: loading
                    ? const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : Column(
                        children: [
                          const Icon(
                            Icons.bolt_rounded,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            'Cash Out Now',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            enabled
                                ? 'Instant · ${fmt.format(available)}'
                                : 'Unavailable',
                            style: TextStyle(
                              color: enabled ? Colors.white70 : Colors.white38,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
        if (!enabled && _disabledReason.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              children: [
                const Icon(Icons.info_outline, size: 14, color: Colors.white38),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    _disabledReason,
                    style: const TextStyle(color: Colors.white38, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Banner extends StatelessWidget {
  final String message;
  final Color color;
  final IconData icon;

  const _Banner({
    required this.message,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        border: Border.all(color: color.withOpacity(0.4)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message, style: TextStyle(color: color, fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

class _PayoutTile extends StatelessWidget {
  final PayoutRecord payout;

  const _PayoutTile({required this.payout});

  static const _card = Color(0xFF1C1F2E);

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '\$');
    final dateFmt = DateFormat('MMM d, yyyy · h:mm a');

    Color statusColor;
    IconData statusIcon;
    switch (payout.status) {
      case 'paid':
        statusColor = const Color(0xFF00C896);
        statusIcon = Icons.check_circle;
        break;
      case 'failed':
        statusColor = Colors.redAccent;
        statusIcon = Icons.cancel;
        break;
      default:
        statusColor = Colors.orange;
        statusIcon = Icons.access_time;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: statusColor.withOpacity(0.15),
            ),
            child: Icon(statusIcon, color: statusColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${payout.payoutType == 'instant' ? 'Instant' : 'Standard'} Payout',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  dateFmt.format(payout.createdAt.toLocal()),
                  style: const TextStyle(color: Colors.white38, fontSize: 11),
                ),
                if (payout.status == 'failed' && payout.failureMessage != null)
                  Text(
                    payout.failureMessage!,
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Text(
            fmt.format(payout.amount),
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyPayouts extends StatelessWidget {
  const _EmptyPayouts();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Column(
          children: [
            Icon(Icons.receipt_long, color: Colors.white24, size: 48),
            SizedBox(height: 12),
            Text(
              'No payouts yet',
              style: TextStyle(color: Colors.white38, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Cash Out Confirmation Dialog ───────────────────────────────────────────

class _CashOutDialog extends StatelessWidget {
  final double amount;

  const _CashOutDialog({required this.amount});

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: '\$');
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1F2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: const Text(
        'Confirm Cash Out',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt_rounded, color: Color(0xFF00C896), size: 48),
          const SizedBox(height: 12),
          Text(
            fmt.format(amount),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This will be transferred to your debit card via Stripe Instant Payout. Funds typically arrive within minutes.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white60, fontSize: 13),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00C896),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text(
            'Cash Out Now',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
