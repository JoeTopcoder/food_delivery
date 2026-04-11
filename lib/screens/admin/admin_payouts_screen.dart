import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../config/app_constants.dart';
import '../../providers/payout_provider.dart';
import '../../services/payout_service.dart';
import '../../utils/friendly_error.dart';

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
      backgroundColor: const Color(0xFFF3F4F6),
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
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(friendlyError(e))),
        data: (allPayouts) {
          final filtered = _statusFilter == null
              ? allPayouts
              : allPayouts.where((p) => p.status == _statusFilter).toList();

          if (filtered.isEmpty) {
            return const Center(
              child: Text(
                'No payout requests',
                style: TextStyle(color: Colors.grey),
              ),
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
        color: Colors.white,
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
          // ── Amount + details ──
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
                  style: TextStyle(fontSize: 12, color: Colors.grey[500]),
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
                  color: Colors.grey[600],
                ),
              ),
            ),
          // ── Action buttons ──
          if (p.status == 'pending' || p.status == 'approved')
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
                    Expanded(
                      child: _actionBtn(
                        label: 'Pay via NCB',
                        color: const Color(0xFF6366F1),
                        icon: Icons.open_in_new,
                        onTap: () => _openNcbPayoutDialog(p),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _actionBtn(
                        label: 'Mark Complete',
                        color: const Color(0xFF22C55E),
                        icon: Icons.check_circle,
                        onTap: () => _markComplete(p.id),
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
                color: Colors.grey[500],
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

  Future<void> _openNcbPayoutDialog(dynamic payout) async {
    final amount = NumberFormat.currency(
      symbol: 'JMD ',
      decimalDigits: 2,
    ).format(payout.amount);
    final details =
        'Bank: ${payout.bankName ?? 'N/A'}\n'
        'Branch: ${payout.bankBranch ?? 'N/A'}\n'
        'Account: ${payout.bankAccountNumber ?? 'N/A'}\n'
        'Holder: ${payout.bankAccountHolder ?? 'N/A'}\n'
        'Amount: $amount';

    if (!mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(
              Icons.account_balance_rounded,
              color: Color(0xFF6366F1),
              size: 22,
            ),
            SizedBox(width: 8),
            Text('NCB Payout'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send payment via NCB gateway:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(details, style: const TextStyle(fontSize: 13)),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFFF59E0B),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This will send the payment directly to the recipient\'s bank account via NCB.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF92400E)),
                    ),
                  ),
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
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Process the payout via NCB
    setState(() => _processing = true);
    try {
      await ref.read(payoutServiceProvider).processPayout(payout.id);
      _snack('Payment sent via NCB successfully!', const Color(0xFF22C55E));
      widget.onAction();
    } catch (e) {
      _snack('NCB payout failed. Please try again.', Colors.red);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _markComplete(String id) async {
    setState(() => _processing = true);
    try {
      await ref.read(payoutServiceProvider).markPayoutCompleted(payoutId: id);
      _snack('Payout marked complete', Colors.green);
      widget.onAction();
    } catch (e) {
      _snack(friendlyError(e), Colors.red);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
    }
  }
}
