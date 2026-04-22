// driver_wallet_screen.dart — Full Stripe Connect wallet screen
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:intl/intl.dart';
import '../../models/driver_model.dart';
import '../../providers/driver_provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/payout_service.dart'
    show
        StripePayoutService,
        StripePayoutException,
        PayoutRecord,
        DriverPayoutMethod;
import '../../utils/friendly_error.dart';
import '../../config/app_constants.dart';
import 'driver_kyc_screen.dart';
import 'driver_payout_methods_screen.dart';

// ── Providers ──────────────────────────────────────────────────────────────

final stripeStatusProvider = FutureProvider.autoDispose<Map<String, dynamic>>((
  ref,
) async {
  return StripePayoutService.instance.getStripeStatus();
});

final payoutMethodsProvider =
    FutureProvider.autoDispose<List<DriverPayoutMethod>>((ref) async {
      return StripePayoutService.instance.getPayoutMethods();
    });

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
  bool _payingOut = false;
  bool _creatingAccount = false;
  String? _errorMessage;
  String? _successMessage;

  static const _bg = Color(0xFF0F1117);
  static const _cardBg = Color(0xFF1C1F2E);
  static const _accent = Color(0xFF6C63FF);
  static const _green = Color(0xFF00C896);

  // ── Create Stripe account ─────────────────────────────────────────────

  Future<void> _createAccount() async {
    setState(() {
      _creatingAccount = true;
      _errorMessage = null;
    });
    try {
      await StripePayoutService.instance.createStripeAccount();
      ref.invalidate(stripeStatusProvider);
      ref.invalidate(driverProfileProvider(ref.read(currentUserIdProvider)!));
      setState(
        () => _successMessage =
            'Account created! Complete your identity verification to enable payouts.',
      );
    } catch (e) {
      setState(() => _errorMessage = friendlyError(e));
    } finally {
      if (mounted) setState(() => _creatingAccount = false);
    }
  }

  // ── Add debit card ────────────────────────────────────────────────────

  Future<void> _addCard() async {
    final pubKey = AppConstants.stripePublishableKey;
    if (pubKey.isEmpty) {
      setState(
        () => _errorMessage = 'Stripe is not configured. Contact support.',
      );
      return;
    }
    Stripe.publishableKey = pubKey;
    await Stripe.instance.applySettings();
    if (!mounted) return;

    final tokenId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AddCardSheet(),
    );
    if (tokenId == null || !mounted) return;

    setState(() {
      _creatingAccount = true;
      _errorMessage = null;
    });
    try {
      final result = await StripePayoutService.instance.addDebitCard(tokenId);
      final last4 = result['last4'] as String?;
      ref.invalidate(stripeStatusProvider);
      ref.invalidate(payoutMethodsProvider);
      ref.invalidate(driverProfileProvider(ref.read(currentUserIdProvider)!));
      setState(
        () => _successMessage = last4 != null
            ? 'Debit card •••• $last4 added! You can now cash out instantly.'
            : 'Debit card added! You can now cash out instantly.',
      );
    } catch (e) {
      setState(() => _errorMessage = friendlyError(e));
    } finally {
      if (mounted) setState(() => _creatingAccount = false);
    }
  }

  // ── Cash out ──────────────────────────────────────────────────────────

  Future<void> _cashOut(
    String payoutType,
    double available,
    Driver driver,
  ) async {
    if ((payoutType == 'instant') && !driver.stripeDebitCardAdded) {
      setState(
        () => _errorMessage = 'Add a debit card first for instant payouts.',
      );
      return;
    }

    final minCents = 1000; // $10 minimum
    if ((available * 100).round() < minCents) {
      setState(() => _errorMessage = 'Minimum payout is \$10.00.');
      return;
    }

    final amountCents = (available * 100).round();
    final fee = payoutType == 'instant' ? (amountCents * 0.01).round() : 0;
    final netCents = amountCents - fee;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => _CashOutDialog(
        amountCents: amountCents,
        feeCents: fee,
        netCents: netCents,
        payoutType: payoutType,
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _payingOut = true;
      _errorMessage = null;
      _successMessage = null;
    });
    try {
      await StripePayoutService.instance.requestPayout(
        amountCents: netCents,
        payoutType: payoutType,
      );
      ref.invalidate(driverProfileProvider(ref.read(currentUserIdProvider)!));
      ref.invalidate(payoutHistoryProvider(driver.id));
      setState(
        () => _successMessage =
            '${payoutType == 'instant' ? 'Instant' : 'Standard'} payout of \$${(netCents / 100).toStringAsFixed(2)} initiated!',
      );
    } on StripePayoutException catch (ex) {
      if (ex.fallbackAvailable && payoutType == 'instant' && mounted) {
        final useStd = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: _cardBg,
            title: const Text(
              'Instant Unavailable',
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              '${ex.message}\n\nTry standard payout (2-5 business days)?',
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
        if (useStd == true) await _cashOut('standard', available, driver);
        return;
      }
      setState(() => _errorMessage = ex.message);
    } catch (e) {
      setState(() => _errorMessage = friendlyError(e));
    } finally {
      if (mounted) setState(() => _payingOut = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────

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
    final statusAsync = ref.watch(stripeStatusProvider);
    final methodsAsync = ref.watch(payoutMethodsProvider);
    final payoutsAsync = ref.watch(payoutHistoryProvider(driver.id));

    return Scaffold(
      backgroundColor: _bg,
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(driverProfileProvider(currentUserId));
          ref.invalidate(stripeStatusProvider);
          ref.invalidate(payoutMethodsProvider);
          ref.invalidate(payoutHistoryProvider(driver.id));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              floating: true,
              backgroundColor: _bg,
              foregroundColor: Colors.white,
              title: const Text(
                'My Wallet',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // Balance card
                  _BalanceCard(
                    available: available,
                    totalEarned: totalEarned,
                    totalPaidOut: totalPaidOut,
                  ),
                  const SizedBox(height: 20),

                  // Feedback banners
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

                  // Stripe account status card
                  statusAsync.when(
                    loading: () => const SizedBox(
                      height: 60,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (e, _) => _Banner(
                      message: friendlyError(e),
                      color: Colors.orange,
                      icon: Icons.warning_amber,
                    ),
                    data: (status) => _StripeAccountCard(
                      driver: driver,
                      status: status,
                      loading: _creatingAccount,
                      onCreateAccount: _createAccount,
                      onCompleteKyc: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DriverKycScreen(),
                          ),
                        );
                        ref.invalidate(stripeStatusProvider);
                        ref.invalidate(driverProfileProvider);
                      },
                      onManageMethods: () async {
                        await Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const DriverPayoutMethodsScreen(),
                          ),
                        );
                        ref.invalidate(stripeStatusProvider);
                        ref.invalidate(payoutMethodsProvider);
                        ref.invalidate(driverProfileProvider);
                      },
                      onAddCard: _addCard,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Cash out buttons
                  if (driver.payoutsEnabled) ...[
                    _CashOutButton(
                      label: 'Cash Out Instantly',
                      subtitle: '1% fee · Arrives in minutes',
                      icon: Icons.bolt_rounded,
                      color: _green,
                      enabled: available >= 10 && driver.stripeDebitCardAdded,
                      loading: _payingOut,
                      onTap: () => _cashOut('instant', available, driver),
                    ),
                    const SizedBox(height: 10),
                    _CashOutButton(
                      label: 'Cash Out to Bank',
                      subtitle: 'Free · 2–5 business days',
                      icon: Icons.account_balance,
                      color: _accent,
                      enabled: available >= 10,
                      loading: _payingOut,
                      onTap: () => _cashOut('standard', available, driver),
                    ),
                  ] else
                    _InfoBanner(
                      message: driver.stripeAccountId == null
                          ? 'Set up your payout account to cash out earnings.'
                          : 'Complete identity verification to enable payouts.',
                      icon: Icons.info_outline,
                    ),

                  const SizedBox(height: 24),

                  // Payout methods summary
                  methodsAsync.when(
                    loading: () => const SizedBox.shrink(),
                    error: (_, __) => const SizedBox.shrink(),
                    data: (methods) => methods.isEmpty
                        ? const SizedBox.shrink()
                        : _PayoutMethodsSummary(methods: methods),
                  ),

                  const SizedBox(height: 24),

                  // Payout history
                  const Text(
                    'Transaction History',
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
                        ? const _EmptyHistory()
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

// ── Balance Card ────────────────────────────────────────────────────────────

class _BalanceCard extends StatelessWidget {
  final double available, totalEarned, totalPaidOut;
  const _BalanceCard({
    required this.available,
    required this.totalEarned,
    required this.totalPaidOut,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: r'$');
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
            color: const Color(0xFF6C63FF).withValues(alpha: 0.35),
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
              _Stat(label: 'Total Earned', value: fmt.format(totalEarned)),
              const SizedBox(width: 24),
              _Stat(label: 'Paid Out', value: fmt.format(totalPaidOut)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 11)),
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

// ── Stripe Account Card ─────────────────────────────────────────────────────

class _StripeAccountCard extends StatelessWidget {
  final Driver driver;
  final Map<String, dynamic> status;
  final bool loading;
  final VoidCallback onCreateAccount;
  final VoidCallback onCompleteKyc;
  final VoidCallback onManageMethods;
  final VoidCallback onAddCard;

  const _StripeAccountCard({
    required this.driver,
    required this.status,
    required this.loading,
    required this.onCreateAccount,
    required this.onCompleteKyc,
    required this.onManageMethods,
    required this.onAddCard,
  });

  static const _cardBg = Color(0xFF1C1F2E);
  static const _accent = Color(0xFF6C63FF);
  static const _green = Color(0xFF00C896);

  @override
  Widget build(BuildContext context) {
    final accountStatus = driver.stripeAccountStatus ?? 'not_connected';
    final hasAccount = driver.stripeAccountId != null;
    final payoutsEnabled = driver.payoutsEnabled;
    final hasCard = driver.stripeDebitCardAdded;

    Color chipColor;
    String chipLabel;
    switch (accountStatus) {
      case 'active':
        chipColor = _green;
        chipLabel = 'Active';
        break;
      case 'pending':
        chipColor = Colors.orange;
        chipLabel = 'Pending Verification';
        break;
      case 'restricted':
        chipColor = Colors.redAccent;
        chipLabel = 'Action Required';
        break;
      default:
        chipColor = Colors.white38;
        chipLabel = 'Not Set Up';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet,
                color: _accent,
                size: 20,
              ),
              const SizedBox(width: 10),
              const Text(
                'Payout Account',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              _Chip(label: chipLabel, color: chipColor),
            ],
          ),
          const SizedBox(height: 12),

          if (!hasAccount) ...[
            const Text(
              'Connect a payout account to receive your earnings.',
              style: TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 12),
            _ActionButton(
              label: 'Set Up Payout Account',
              icon: Icons.add,
              color: _accent,
              loading: loading,
              onTap: onCreateAccount,
            ),
          ] else ...[
            _StatusRow(
              label: 'Identity Verified',
              ok: payoutsEnabled,
              notOkText: 'Complete ID verification',
            ),
            const SizedBox(height: 4),
            _StatusRow(
              label: 'Debit Card Added',
              ok: hasCard,
              notOkText: 'Add a debit card for instant payouts',
            ),
            const SizedBox(height: 12),
            if (!payoutsEnabled)
              _ActionButton(
                label: 'Verify Identity (KYC)',
                icon: Icons.verified_user,
                color: Colors.orange,
                loading: loading,
                onTap: onCompleteKyc,
              ),
            if (payoutsEnabled && !hasCard) ...[
              _ActionButton(
                label: 'Add Debit Card (Instant)',
                icon: Icons.credit_card,
                color: _green,
                loading: loading,
                onTap: onAddCard,
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              onPressed: onManageMethods,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white54,
                side: const BorderSide(color: Colors.white24),
                padding: const EdgeInsets.symmetric(vertical: 10),
                minimumSize: const Size(double.infinity, 0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              icon: const Icon(Icons.tune, size: 16),
              label: const Text('Manage Payout Methods'),
            ),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(label, style: TextStyle(color: color, fontSize: 11)),
  );
}

class _StatusRow extends StatelessWidget {
  final String label;
  final bool ok;
  final String? notOkText;
  const _StatusRow({required this.label, required this.ok, this.notOkText});
  @override
  Widget build(BuildContext context) => Row(
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
            if (!ok && notOkText != null)
              Text(
                notOkText!,
                style: const TextStyle(color: Colors.orange, fontSize: 11),
              ),
          ],
        ),
      ),
    ],
  );
}

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final bool loading;
  final VoidCallback onTap;
  const _ActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.loading,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: ElevatedButton.icon(
      onPressed: loading ? null : onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      icon: loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Icon(icon, size: 18),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
    ),
  );
}

// ── Cash Out Button ─────────────────────────────────────────────────────────

class _CashOutButton extends StatelessWidget {
  final String label, subtitle;
  final IconData icon;
  final Color color;
  final bool enabled, loading;
  final VoidCallback? onTap;
  const _CashOutButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.enabled,
    required this.loading,
    this.onTap,
  });
  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    decoration: BoxDecoration(
      gradient: enabled
          ? LinearGradient(
              colors: [color, color.withValues(alpha: 0.7)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : null,
      color: enabled ? null : const Color(0xFF2A2D3E),
      borderRadius: BorderRadius.circular(14),
      boxShadow: enabled
          ? [
              BoxShadow(
                color: color.withValues(alpha: 0.3),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ]
          : null,
    ),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: enabled && !loading ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          child: loading
              ? const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : Row(
                  children: [
                    Icon(icon, color: Colors.white, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              color: enabled ? Colors.white : Colors.white38,
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            subtitle,
                            style: TextStyle(
                              color: enabled ? Colors.white60 : Colors.white24,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      color: enabled ? Colors.white60 : Colors.white24,
                    ),
                  ],
                ),
        ),
      ),
    ),
  );
}

// ── Payout Methods Summary ──────────────────────────────────────────────────

class _PayoutMethodsSummary extends StatelessWidget {
  final List<DriverPayoutMethod> methods;
  const _PayoutMethodsSummary({required this.methods});
  static const _cardBg = Color(0xFF1C1F2E);

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Text(
        'Payout Methods',
        style: TextStyle(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 10),
      ...methods.map(
        (m) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                m.isCard ? Icons.credit_card : Icons.account_balance,
                color: const Color(0xFF6C63FF),
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.isCard
                          ? '${m.brand ?? 'Card'} •••• ${m.last4}'
                          : '${m.bankName ?? 'Bank'} •••• ${m.last4}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      m.isCard
                          ? 'Instant payouts'
                          : 'Standard payouts (2–5 days)',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (m.isDefault)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white12,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Default',
                    style: TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                ),
            ],
          ),
        ),
      ),
      const SizedBox(height: 8),
    ],
  );
}

// ── Info & Feedback ─────────────────────────────────────────────────────────

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
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      border: Border.all(color: color.withValues(alpha: 0.4)),
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

class _InfoBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  const _InfoBanner({required this.message, required this.icon});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(color: Colors.white54, fontSize: 13),
          ),
        ),
      ],
    ),
  );
}

// ── Payout Tile ─────────────────────────────────────────────────────────────

class _PayoutTile extends StatelessWidget {
  final PayoutRecord payout;
  const _PayoutTile({required this.payout});
  static const _cardBg = Color(0xFF1C1F2E);

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: r'$');
    final dateFmt = DateFormat('MMM d, yyyy · h:mm a');
    Color c;
    IconData ico;
    switch (payout.status) {
      case 'paid':
        c = const Color(0xFF00C896);
        ico = Icons.check_circle;
        break;
      case 'failed':
        c = Colors.redAccent;
        ico = Icons.cancel;
        break;
      default:
        c = Colors.orange;
        ico = Icons.access_time;
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.withValues(alpha: 0.15),
            ),
            child: Icon(ico, color: c, size: 20),
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
              color: c,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory();
  @override
  Widget build(BuildContext context) => const Center(
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

// ── Cash Out Confirmation Dialog ────────────────────────────────────────────

class _CashOutDialog extends StatelessWidget {
  final int amountCents, feeCents, netCents;
  final String payoutType;
  const _CashOutDialog({
    required this.amountCents,
    required this.feeCents,
    required this.netCents,
    required this.payoutType,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat.currency(symbol: r'$');
    return AlertDialog(
      backgroundColor: const Color(0xFF1C1F2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        '${payoutType == 'instant' ? 'Instant' : 'Standard'} Payout',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            payoutType == 'instant'
                ? Icons.bolt_rounded
                : Icons.account_balance,
            color: const Color(0xFF00C896),
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            fmt.format(amountCents / 100),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (feeCents > 0) ...[
            const SizedBox(height: 4),
            Text(
              'Fee: ${fmt.format(feeCents / 100)}',
              style: const TextStyle(color: Colors.orange, fontSize: 13),
            ),
            Text(
              'You receive: ${fmt.format(netCents / 100)}',
              style: const TextStyle(
                color: Color(0xFF00C896),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            payoutType == 'instant'
                ? 'Funds arrive to your debit card within minutes.'
                : 'Funds arrive via ACH in 2–5 business days.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 13),
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
            'Confirm',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}

// ── Add Card Bottom Sheet ───────────────────────────────────────────────────

class _AddCardSheet extends StatefulWidget {
  const _AddCardSheet();
  @override
  State<_AddCardSheet> createState() => _AddCardSheetState();
}

class _AddCardSheetState extends State<_AddCardSheet> {
  bool _cardComplete = false, _loading = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tokenData = await Stripe.instance.createToken(
        const CreateTokenParams.card(
          params: CardTokenParams(type: TokenType.Card),
        ),
      );
      if (tokenData.id.isEmpty)
        throw Exception('No token returned from Stripe.');
      if (mounted) Navigator.pop(context, tokenData.id);
    } catch (e) {
      setState(() {
        _error = e
            .toString()
            .replaceFirst('Exception: ', '')
            .replaceFirst('StripeException: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
    child: Container(
      decoration: const BoxDecoration(
        color: Color(0xFF1C1F2E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Add Debit Card',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Visa or Mastercard debit card only.\nUsed for instant payouts.',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          CardField(
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              fillColor: Color(0xFF0F1117),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Color(0xFF2E3147)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Color(0xFF2E3147)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
                borderSide: BorderSide(color: Color(0xFF6C63FF)),
              ),
            ),
            onCardChanged: (d) =>
                setState(() => _cardComplete = d?.complete == true),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 13),
            ),
          ],
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_cardComplete && !_loading) ? _submit : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                disabledBackgroundColor: const Color(
                  0xFF6C63FF,
                ).withValues(alpha: 0.4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Save Card',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    ),
  );
}
