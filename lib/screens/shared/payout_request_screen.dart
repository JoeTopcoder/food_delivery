import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../providers/auth_provider.dart';
import '../../providers/driver_provider.dart';
import '../../providers/payout_provider.dart';
import '../../providers/restaurant_provider.dart';
import '../../utils/friendly_error.dart';
import '../../services/payout_service.dart';
import '../../utils/app_theme.dart';
import 'bank_info_screen.dart';
import '../../utils/app_feedback_widgets.dart';

class PayoutRequestScreen extends ConsumerStatefulWidget {
  final String role; // 'driver' or 'restaurant'
  const PayoutRequestScreen({super.key, required this.role});

  @override
  ConsumerState<PayoutRequestScreen> createState() =>
      _PayoutRequestScreenState();
}

class _PayoutRequestScreenState extends ConsumerState<PayoutRequestScreen> {
  final _amountCtrl = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  bool get _isDriver => widget.role == 'driver';
  Color get _accentColor =>
      _isDriver ? AppTheme.primaryColor : const Color(0xFF10B981);

  @override
  Widget build(BuildContext context) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Request Payout',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: _accentColor,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isDriver ? _buildDriverBody(userId) : _buildRestaurantBody(userId),
    );
  }

  // ── Driver ──────────────────────────────────────────────────

  Widget _buildDriverBody(String userId) {
    final driverAsync = ref.watch(driverProfileProvider(userId));
    return driverAsync.when(
      loading: () =>
          const AppLoadingIndicator(message: 'Loading driver profile...'),
      error: (e, _) => AppErrorState(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(driverProfileProvider(userId)),
      ),
      data: (driver) {
        if (driver == null) {
          return const Center(child: Text('No driver profile'));
        }
        final totalEarnings = driver.totalEarnings ?? 0.0;
        final totalPaidOut = driver.totalPaidOut ?? 0.0;
        final available = totalEarnings - totalPaidOut;
        final hasBankInfo =
            driver.bankAccountNumber != null &&
            driver.bankAccountNumber!.isNotEmpty;

        return _buildContent(
          totalEarnings: totalEarnings,
          totalPaidOut: totalPaidOut,
          available: available,
          hasBankInfo: hasBankInfo,
          userId: userId,
          onSubmit: () => _submitDriverPayout(
            userId: userId,
            driverId: driver.id,
            available: available,
            driver: driver,
          ),
        );
      },
    );
  }

  // ── Restaurant ──────────────────────────────────────────────

  Widget _buildRestaurantBody(String userId) {
    final restAsync = ref.watch(restaurantByOwnerProvider(userId));
    return restAsync.when(
      loading: () =>
          const AppLoadingIndicator(message: 'Loading restaurant profile...'),
      error: (e, _) => AppErrorState(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(restaurantByOwnerProvider(userId)),
      ),
      data: (restaurant) {
        if (restaurant == null) {
          return const Center(child: Text('No restaurant profile'));
        }

        final earningsAsync = ref.watch(
          restaurantEarningsProvider(restaurant.id),
        );
        final paidOutAsync = ref.watch(
          restaurantTotalPaidOutProvider(restaurant.id),
        );

        return earningsAsync.when(
          loading: () =>
              const AppLoadingIndicator(message: 'Loading earnings...'),
          error: (e, _) => AppErrorState(
            message: friendlyError(e),
            onRetry: () =>
                ref.invalidate(restaurantEarningsProvider(restaurant.id)),
          ),
          data: (totalEarnings) {
            final totalPaidOut = paidOutAsync.valueOrNull ?? 0.0;
            final available = totalEarnings - totalPaidOut;
            final hasBankInfo =
                restaurant.bankAccountNumber != null &&
                restaurant.bankAccountNumber!.isNotEmpty;

            return _buildContent(
              totalEarnings: totalEarnings,
              totalPaidOut: totalPaidOut,
              available: available,
              hasBankInfo: hasBankInfo,
              userId: userId,
              onSubmit: () => _submitRestaurantPayout(
                userId: userId,
                restaurantId: restaurant.id,
                available: available,
                restaurant: restaurant,
              ),
            );
          },
        );
      },
    );
  }

  // ── Shared UI ───────────────────────────────────────────────

  Widget _buildContent({
    required double totalEarnings,
    required double totalPaidOut,
    required double available,
    required bool hasBankInfo,
    required String userId,
    required VoidCallback onSubmit,
  }) {
    final fmt = NumberFormat('#,##0.00');
    final payoutsAsync = ref.watch(myPayoutsProvider(userId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(myPayoutsProvider(userId));
        if (_isDriver) {
          ref.invalidate(driverProfileProvider(userId));
        } else {
          ref.invalidate(restaurantByOwnerProvider(userId));
        }
      },
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Earnings summary card ──
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: _isDriver
                    ? [AppTheme.primaryColor, const Color(0xFF1E40AF)]
                    : [const Color(0xFF10B981), const Color(0xFF059669)],
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Text(
                  'Available Balance',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 6),
                Text(
                  '${AppConstants.currencySymbol}${fmt.format(available < 0 ? 0 : available)}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _summaryCol('Total Earned', fmt.format(totalEarnings)),
                    Container(width: 1, height: 30, color: Colors.white30),
                    _summaryCol('Paid Out', fmt.format(totalPaidOut)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // ── Bank info check ──
          if (!hasBankInfo) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFDBA74)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFF59E0B),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Bank info required',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Add your banking details before requesting a payout.',
                          style: TextStyle(fontSize: 12),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 34,
                          child: ElevatedButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    BankInfoScreen(role: widget.role),
                              ),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _accentColor,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: const Text(
                              'Add Bank Info',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

          // ── Request payout form ──
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Request Payout',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    prefixText: '${AppConstants.currencySymbol} ',
                    hintText: '0.00',
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD1D5DB)),
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Max: ${AppConstants.currencySymbol}${fmt.format(available < 0 ? 0 : available)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (!hasBankInfo || _submitting || available <= 0)
                        ? null
                        : onSubmit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Submit Request',
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
          const SizedBox(height: 24),

          // ── Payout history ──
          const Text(
            'Payout History',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 10),
          payoutsAsync.when(
            loading: () =>
                const AppLoadingIndicator(message: 'Loading payouts...'),
            error: (e, _) => AppErrorState(
              message: friendlyError(e),
              onRetry: () => ref.invalidate(myPayoutsProvider(userId)),
            ),
            data: (payouts) {
              if (payouts.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.account_balance_wallet_rounded,
                  title: 'No payout requests yet',
                  subtitle: 'Submit your first payout request above',
                );
              }
              return Column(
                children: payouts.map((p) => _payoutTile(p, fmt)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _summaryCol(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          '${AppConstants.currencySymbol}$value',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }

  Widget _payoutTile(PayoutRequest p, NumberFormat fmt) {
    final (Color bg, Color fg, IconData icon) = switch (p.status) {
      'pending' => (
        const Color(0xFFFFF7ED),
        const Color(0xFFF59E0B),
        Icons.schedule,
      ),
      'approved' => (
        const Color(0xFFEFF6FF),
        const Color(0xFF3B82F6),
        Icons.thumb_up_outlined,
      ),
      'processing' => (
        const Color(0xFFEFF6FF),
        const Color(0xFF6366F1),
        Icons.sync,
      ),
      'completed' => (
        const Color(0xFFF0FDF4),
        const Color(0xFF22C55E),
        Icons.check_circle,
      ),
      'rejected' => (
        const Color(0xFFFEF2F2),
        const Color(0xFFEF4444),
        Icons.cancel,
      ),
      'failed' => (
        const Color(0xFFFEF2F2),
        const Color(0xFFEF4444),
        Icons.error,
      ),
      _ => (Colors.grey.shade100, Colors.grey, Icons.help_outline),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${AppConstants.currencySymbol}${fmt.format(p.amount)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  DateFormat('MMM d, yyyy · h:mm a').format(p.createdAt),
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                if (p.adminNotes != null && p.adminNotes!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      p.adminNotes!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              p.status[0].toUpperCase() + p.status.substring(1),
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Submit logic ────────────────────────────────────────────

  Future<void> _submitDriverPayout({
    required String userId,
    required String driverId,
    required double available,
    required dynamic driver,
  }) async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _showError('Enter a valid amount');
      return;
    }
    if (amount > available) {
      _showError('Amount exceeds available balance');
      return;
    }
    setState(() => _submitting = true);
    try {
      final svc = ref.read(payoutServiceProvider);
      await svc.requestDriverPayout(
        userId: userId,
        driverId: driverId,
        amount: amount,
        bankName: driver.bankName ?? '',
        bankBranch: driver.bankBranch ?? '',
        accountNumber: driver.bankAccountNumber ?? '',
        accountHolder: driver.bankAccountHolder ?? '',
        accountType: driver.bankAccountType ?? 'checking',
      );
      _amountCtrl.clear();
      ref.invalidate(myPayoutsProvider(userId));
      if (mounted) {
        AppSnackbar.success(context, 'Payout request submitted!');
      }
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _submitRestaurantPayout({
    required String userId,
    required String restaurantId,
    required double available,
    required dynamic restaurant,
  }) async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      _showError('Enter a valid amount');
      return;
    }
    if (amount > available) {
      _showError('Amount exceeds available balance');
      return;
    }
    setState(() => _submitting = true);
    try {
      final svc = ref.read(payoutServiceProvider);
      await svc.requestRestaurantPayout(
        userId: userId,
        restaurantId: restaurantId,
        amount: amount,
        bankName: restaurant.bankName ?? '',
        bankBranch: restaurant.bankBranch ?? '',
        accountNumber: restaurant.bankAccountNumber ?? '',
        accountHolder: restaurant.bankAccountHolder ?? '',
        accountType: restaurant.bankAccountType ?? 'checking',
      );
      _amountCtrl.clear();
      ref.invalidate(myPayoutsProvider(userId));
      if (mounted) {
        AppSnackbar.success(context, 'Payout request submitted!');
      }
    } catch (e) {
      _showError('$e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String msg) {
    if (mounted) {
      AppSnackbar.error(context, msg);
    }
  }
}
