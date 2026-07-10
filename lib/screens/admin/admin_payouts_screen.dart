import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../providers/payout_provider.dart';
import '../../services/payment/payout_service.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';


class AdminPayoutsScreen extends ConsumerStatefulWidget {
  const AdminPayoutsScreen({super.key});

  @override
  ConsumerState<AdminPayoutsScreen> createState() => _AdminPayoutsScreenState();
}

class _AdminPayoutsScreenState extends ConsumerState<AdminPayoutsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  final _tabs = const [
    'All',
    'Pending',
    'Approved',
    'Processing',
    'Completed',
    'Rejected',
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  String? get _statusFilter {
    final idx = _tabCtrl.index;
    if (idx == 0) return null;
    return _tabs[idx].toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final payoutsAsync = ref.watch(allPayoutsProvider);
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Payout Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabAlignment: TabAlignment.start,
          tabs: _tabs.map((t) => Tab(text: t)).toList(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(allPayoutsProvider),
          ),
        ],
      ),
      body: payoutsAsync.when(
        loading: () => const AppLoadingIndicator(message: 'Loading payouts...'),
        error: (e, _) => AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(allPayoutsProvider),
        ),
        data: (allPayouts) {
          final filtered = _statusFilter == null
              ? allPayouts
              : allPayouts.where((p) => p.status == _statusFilter).toList();

          if (filtered.isEmpty) {
            return const AppEmptyState(
              icon: Icons.payments_rounded,
              title: 'No payout requests',
              subtitle: 'Payout requests will appear here',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: filtered.length,
            itemBuilder: (_, i) => _PayoutCard(
              payout: filtered[i],
              fmt: fmt,
              onAction: () => ref.invalidate(allPayoutsProvider),
            ),
          );
        },
      ),
    );
  }
}

// ── Balance badge (restaurant only) ──────────────────────────────────────────

class _RestaurantBalanceBadge extends ConsumerWidget {
  final String restaurantId;
  const _RestaurantBalanceBadge({required this.restaurantId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balanceAsync = ref.watch(
      restaurantAvailableBalanceProvider(restaurantId),
    );
    return balanceAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (balance) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Row(
          children: [
            const Icon(
              Icons.account_balance_wallet_rounded,
              size: 13,
              color: Color(0xFF0EA5E9),
            ),
            const SizedBox(width: 4),
            Text(
              'Available balance: ${AppConstants.currencySymbol}${NumberFormat('#,##0.00').format(balance)}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0EA5E9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Payout card ───────────────────────────────────────────────────────────────

class _PayoutCard extends ConsumerStatefulWidget {
  final PayoutRequest payout;
  final NumberFormat fmt;
  final VoidCallback onAction;

  const _PayoutCard({
    required this.payout,
    required this.fmt,
    required this.onAction,
  });

  @override
  ConsumerState<_PayoutCard> createState() => _PayoutCardState();
}

class _PayoutCardState extends ConsumerState<_PayoutCard> {
  bool _processing = false;
  bool _hasStripeAccount = false;

  @override
  void initState() {
    super.initState();
    if (widget.payout.requesterType == 'driver') {
      _loadStripeAccountStatus();
    }
  }

  Future<void> _loadStripeAccountStatus() async {
    final row = await Supabase.instance.client
        .from('stripe_connected_accounts')
        .select('onboarding_status, payouts_enabled')
        .eq('user_id', widget.payout.requesterId)
        .eq('role', 'driver')
        .maybeSingle();
    if (mounted) {
      setState(() {
        _hasStripeAccount = row != null &&
            row['onboarding_status'] == 'complete' &&
            (row['payouts_enabled'] as bool? ?? false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payout;
    final fmt = widget.fmt;

    final (Color bg, Color fg) = switch (p.status) {
      'pending' => (const Color(0xFFFFF7ED), const Color(0xFFF59E0B)),
      'approved' => (const Color(0xFFEFF6FF), const Color(0xFF3B82F6)),
      'processing' => (const Color(0xFFEFF6FF), const Color(0xFF6366F1)),
      'completed' => (const Color(0xFFF0FDF4), const Color(0xFF22C55E)),
      'rejected' => (const Color(0xFFFEF2F2), const Color(0xFFEF4444)),
      'failed' => (const Color(0xFFFEF2F2), const Color(0xFFEF4444)),
      _ => (Colors.grey.shade100, Colors.grey),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: p.requesterType == 'driver'
                        ? const Color(0xFFEFF6FF)
                        : const Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    p.requesterType == 'driver'
                        ? '🚗 Driver'
                        : '🍽️ Restaurant',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: p.requesterType == 'driver'
                          ? const Color(0xFF3B82F6)
                          : const Color(0xFF10B981),
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
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
          ),
          // ── Amount + date ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Row(
              children: [
                Text(
                  '${AppConstants.currencySymbol}${fmt.format(p.amount)}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMM d, y').format(p.createdAt),
                  style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          // ── Bank details ──
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _detailRow('Bank', p.bankName),
                  if (p.bankBranch != null && p.bankBranch!.isNotEmpty)
                    _detailRow('Branch', p.bankBranch!),
                  _detailRow('Account', _maskAccount(p.bankAccountNumber)),
                  _detailRow('Holder', p.bankAccountHolder),
                  if (p.bankAccountType != null)
                    _detailRow('Type', p.bankAccountType!),
                ],
              ),
            ),
          ),
          if (p.adminNotes != null && p.adminNotes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                'Note: ${p.adminNotes}',
                style: TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          // ── Available balance badge (restaurant only) ──
          if (p.requesterType == 'restaurant' && p.restaurantId != null)
            _RestaurantBalanceBadge(restaurantId: p.restaurantId!),
          // ── Action buttons ──
          if (p.status == 'pending' ||
              p.status == 'approved' ||
              (p.status == 'processing' && p.requesterType == 'restaurant'))
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Row(
                children: [
                  if (p.status == 'pending') ...[
                    Expanded(
                      child: _actionBtn(
                        label: 'Approve',
                        color: const Color(0xFF22C55E),
                        icon: Icons.check,
                        onTap: () => _approve(p.id),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionBtn(
                        label: 'Reject',
                        color: const Color(0xFFEF4444),
                        icon: Icons.close,
                        onTap: () => _showRejectDialog(p.id),
                      ),
                    ),
                  ],
                  if (p.status == 'approved') ...[
                    if (_hasStripeAccount) ...[
                      Expanded(
                        child: _actionBtn(
                          label: 'Pay via Stripe',
                          color: const Color(0xFF6366F1),
                          icon: Icons.payment_rounded,
                          onTap: () => _openStripePayoutDialog(p),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: _actionBtn(
                        label: 'Mark as Paid',
                        color: const Color(0xFF22C55E),
                        icon: Icons.task_alt_rounded,
                        onTap: () => _openMarkAsPaidDialog(p),
                      ),
                    ),
                  ],
                  if (p.status == 'processing' &&
                      p.requesterType == 'restaurant') ...[
                    Expanded(
                      child: _actionBtn(
                        label: 'Mark Completed',
                        color: const Color(0xFF22C55E),
                        icon: Icons.task_alt_rounded,
                        onTap: () => _markCompleted(p.id),
                      ),
                    ),
                  ],
                ],
              ),
            )
          else
            const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _actionBtn({
    required String label,
    required Color color,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      height: 38,
      child: ElevatedButton.icon(
        onPressed: _processing ? null : onTap,
        icon: _processing
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Icon(icon, size: 16),
        label: Text(label, style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          padding: const EdgeInsets.symmetric(horizontal: 8),
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  String _maskAccount(String acc) {
    if (acc.length <= 4) return acc;
    return '${'*' * (acc.length - 4)}${acc.substring(acc.length - 4)}';
  }

  Future<void> _approve(String id) async {
    setState(() => _processing = true);
    try {
      await ref.read(payoutServiceProvider).approvePayout(id);
      _snack('Payout approved', Colors.green);
      widget.onAction();
    } catch (e) {
      _snack(friendlyError(e), Colors.red);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _markCompleted(String id) async {
    setState(() => _processing = true);
    try {
      await ref.read(payoutServiceProvider).markPayoutCompleted(payoutId: id);
      _snack('Payout marked as completed', Colors.green);
      widget.onAction();
    } catch (e) {
      _snack(friendlyError(e), Colors.red);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _openStripePayoutDialog(PayoutRequest payout) async {
    // Look up the driver's Stripe Connect account
    final db = Supabase.instance.client;
    final accountRow = await db
        .from('stripe_connected_accounts')
        .select('stripe_account_id, onboarding_status, payouts_enabled, country')
        .eq('user_id', payout.requesterId)
        .eq('role', 'driver')
        .maybeSingle();

    if (!mounted) return;

    // No connected account — show setup instructions
    if (accountRow == null) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  color: Color(0xFFF59E0B), size: 22),
              SizedBox(width: 8),
              Text('Stripe Not Set Up'),
            ],
          ),
          content: const Text(
            'This driver hasn\'t connected a Stripe account yet.\n\n'
            'Ask them to open the app → Earnings → "Set Up Payout Account" and '
            'complete Stripe onboarding. Once done, come back and try again.\n\n'
            'Alternatively, use "Mark as Paid" to record a manual bank transfer.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final status = accountRow['onboarding_status'] as String? ?? '';
    final payoutsEnabled = accountRow['payouts_enabled'] as bool? ?? false;

    // Account exists but not fully onboarded
    if (status != 'complete' || !payoutsEnabled) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: Color(0xFFF59E0B), size: 22),
              SizedBox(width: 8),
              Text('Stripe Setup Incomplete'),
            ],
          ),
          content: Text(
            'This driver\'s Stripe account is not ready for payouts.\n\n'
            'Status: $status\nPayouts enabled: $payoutsEnabled\n\n'
            'Ask the driver to finish Stripe onboarding in the app.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    // Account ready — confirm and send via Stripe Connect
    final amtFmt = NumberFormat.currency(
      symbol: '${AppConstants.currencySymbol} ',
      decimalDigits: 2,
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.payment_rounded, color: Color(0xFF6366F1), size: 22),
            SizedBox(width: 8),
            Text('Pay via Stripe'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transfer funds to driver\'s Stripe account:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dialogRow('Amount', amtFmt.format(payout.amount)),
                  _dialogRow('Recipient', payout.bankAccountHolder),
                  _dialogRow('Stripe acct',
                      accountRow['stripe_account_id'] as String? ?? ''),
                  _dialogRow('Country',
                      accountRow['country'] as String? ?? ''),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded, size: 16),
            label: const Text('Send Payment'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _processing = true);
    try {
      final res = await db.functions.invoke(
        'stripe-pay-from-payout-request',
        body: {'payout_request_id': payout.id},
      );
      final data = res.data as Map<String, dynamic>?;
      if (data != null && data.containsKey('error')) {
        throw Exception(data['error']);
      }
      widget.onAction();
      _snack('Payment sent via Stripe', Colors.green);
    } catch (e) {
      _snack('Stripe payment failed: ${friendlyError(e)}', Colors.red);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _openMarkAsPaidDialog(PayoutRequest payout) async {
    final amtFmt = NumberFormat.currency(
      symbol: '${AppConstants.currencySymbol} ',
      decimalDigits: 2,
    );
    final refCtrl = TextEditingController();

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.task_alt_rounded, color: Color(0xFF22C55E), size: 22),
            SizedBox(width: 8),
            Text('Mark as Paid'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Transfer these funds via your bank, then confirm below:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _dialogRow('Amount', amtFmt.format(payout.amount)),
                  _dialogRow('Recipient', payout.bankAccountHolder),
                  _dialogRow('Bank', payout.bankName),
                  if (payout.bankBranch != null && payout.bankBranch!.isNotEmpty)
                    _dialogRow('Branch', payout.bankBranch!),
                  _dialogRow('Account', payout.bankAccountNumber),
                  if (payout.bankAccountType != null)
                    _dialogRow('Type', payout.bankAccountType!),
                ],
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: refCtrl,
              decoration: InputDecoration(
                labelText: 'Transfer reference (optional)',
                hintText: 'e.g. NCB ref #12345',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check_rounded, size: 16),
            label: const Text('Confirm Paid'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF22C55E),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processing = true);
    try {
      await ref.read(payoutServiceProvider).markPayoutCompleted(
        payoutId: payout.id,
        transactionId: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
      );
      widget.onAction();
      _snack('Payout marked as completed', Colors.green);
    } catch (e) {
      _snack('Failed: ${friendlyError(e)}', Colors.red);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Widget _dialogRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              '$label:',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  void _showRejectDialog(String id) {
    final reasonCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Payout'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(
            hintText: 'Reason for rejection (optional)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _processing = true);
              try {
                await ref
                    .read(payoutServiceProvider)
                    .rejectPayout(id, reasonCtrl.text.trim());
                _snack('Payout rejected', Colors.orange);
                widget.onAction();
              } catch (e) {
                _snack(friendlyError(e), Colors.red);
              } finally {
                if (mounted) setState(() => _processing = false);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color color) {
    if (mounted) {
      if (color == Colors.red) {
        AppSnackbar.error(context, msg);
      } else if (color == Colors.orange) {
        AppSnackbar.warning(context, msg);
      } else {
        AppSnackbar.success(context, msg);
      }
    }
  }
}
