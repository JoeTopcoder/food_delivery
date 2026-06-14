import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/app_constants.dart';
import '../../../providers/payout_provider.dart';
import '../../../services/payment/payout_service.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

class WebAdminPayoutsPage extends ConsumerStatefulWidget {
  const WebAdminPayoutsPage({super.key});

  @override
  ConsumerState<WebAdminPayoutsPage> createState() => _WebAdminPayoutsPageState();
}

class _WebAdminPayoutsPageState extends ConsumerState<WebAdminPayoutsPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  static const _tabs = ['All', 'Pending', 'Approved', 'Processing', 'Completed', 'Rejected'];

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

  String? get _filter => _tabCtrl.index == 0 ? null : _tabs[_tabCtrl.index].toLowerCase();

  @override
  Widget build(BuildContext context) {
    final payoutsAsync = ref.watch(allPayoutsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Payout Management', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Approve, process, and track driver & restaurant payouts', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: () => ref.invalidate(allPayoutsProvider),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Summary stats ────────────────────────────────────────────
          payoutsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (payouts) {
              final pending = payouts.where((p) => p.status == 'pending').length;
              final totalPending = payouts.where((p) => p.status == 'pending').fold<double>(0, (s, p) => s + p.amount);
              return Row(
                children: [
                  _StatChip(label: 'Total Requests', value: '${payouts.length}', color: const Color(0xFF6366F1)),
                  const SizedBox(width: 12),
                  _StatChip(label: 'Pending', value: '$pending', color: const Color(0xFFF59E0B)),
                  const SizedBox(width: 12),
                  _StatChip(label: 'Pending Amount', value: '${AppConstants.currencySymbol}${NumberFormat('#,##0.00').format(totalPending)}', color: const Color(0xFFEF4444)),
                ],
              );
            },
          ),
          const SizedBox(height: 20),

          // ── Tabs + Table ─────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Column(
              children: [
                TabBar(
                  controller: _tabCtrl,
                  indicatorColor: AppTheme.primaryColor,
                  indicatorWeight: 3,
                  labelColor: AppTheme.primaryColor,
                  unselectedLabelColor: const Color(0xFF64748B),
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  tabs: _tabs.map((t) => Tab(text: t)).toList(),
                ),
                const Divider(height: 1),
                payoutsAsync.when(
                  loading: () => const SizedBox(height: 200, child: AppLoadingIndicator()),
                  error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allPayoutsProvider)),
                  data: (all) {
                    final list = _filter == null ? all : all.where((p) => p.status == _filter).toList();
                    if (list.isEmpty) {
                      return const SizedBox(height: 200, child: AppEmptyState(icon: Icons.payments_rounded, title: 'No payouts in this category'));
                    }
                    return Column(
                      children: [
                        // Table header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          color: const Color(0xFFF8FAFC),
                          child: const Row(children: [
                            SizedBox(width: 100, child: Text('TYPE', style: _h)),
                            SizedBox(width: 130, child: Text('REQUESTER', style: _h)),
                            SizedBox(width: 120, child: Text('AMOUNT', style: _h)),
                            SizedBox(width: 200, child: Text('BANK', style: _h)),
                            SizedBox(width: 110, child: Text('DATE', style: _h)),
                            SizedBox(width: 100, child: Text('STATUS', style: _h)),
                            Expanded(child: Text('ACTIONS', style: _h, textAlign: TextAlign.right)),
                          ]),
                        ),
                        const Divider(height: 1),
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: list.length,
                          separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                          itemBuilder: (_, i) => _PayoutRow(payout: list[i], onRefresh: () => ref.invalidate(allPayoutsProvider)),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static const _h = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5);
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _StatChip({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}

// ── Payout Row ────────────────────────────────────────────────────────────────

class _PayoutRow extends ConsumerStatefulWidget {
  final PayoutRequest payout;
  final VoidCallback onRefresh;
  const _PayoutRow({required this.payout, required this.onRefresh});

  @override
  ConsumerState<_PayoutRow> createState() => _PayoutRowState();
}

class _PayoutRowState extends ConsumerState<_PayoutRow> {
  bool _loading = false;

  PayoutRequest get p => widget.payout;

  @override
  Widget build(BuildContext context) {
    final statusColors = {
      'pending': const Color(0xFFF59E0B),
      'approved': const Color(0xFF3B82F6),
      'processing': const Color(0xFF6366F1),
      'completed': const Color(0xFF22C55E),
      'rejected': const Color(0xFFEF4444),
      'failed': const Color(0xFFEF4444),
    };
    final statusColor = statusColors[p.status] ?? Colors.grey;
    final isDriver = p.requesterType == 'driver';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isDriver ? const Color(0xFFEFF6FF) : const Color(0xFFF0FDF4),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isDriver ? 'Driver' : 'Restaurant',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isDriver ? const Color(0xFF3B82F6) : const Color(0xFF10B981)),
              ),
            ),
          ),
          SizedBox(width: 130, child: Text(p.bankAccountHolder, style: const TextStyle(fontSize: 13, color: Color(0xFF374151)), overflow: TextOverflow.ellipsis)),
          SizedBox(
            width: 120,
            child: Text('${AppConstants.currencySymbol}${NumberFormat('#,##0.00').format(p.amount)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
          ),
          SizedBox(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(p.bankName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF374151))),
                Text('${_mask(p.bankAccountNumber)} · ${p.bankAccountHolder}', style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
              ],
            ),
          ),
          SizedBox(width: 110, child: Text(DateFormat('MMM d, y').format(p.createdAt), style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))),
          SizedBox(
            width: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(p.status[0].toUpperCase() + p.status.substring(1), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: statusColor)),
            ),
          ),
          Expanded(child: _buildActions(context)),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext ctx) {
    final children = <Widget>[];
    if (_loading) {
      return const Align(alignment: Alignment.centerRight, child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (p.status == 'pending') {
      children.addAll([
        OutlinedButton(
          onPressed: () => _showRejectDialog(ctx),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 10)),
          child: const Text('Reject', style: TextStyle(fontSize: 12)),
        ),
        const SizedBox(width: 6),
        ElevatedButton(
          onPressed: () => _approve(),
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.white, minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 10)),
          child: const Text('Approve', style: TextStyle(fontSize: 12)),
        ),
      ]);
    } else if (p.status == 'approved') {
      children.add(ElevatedButton.icon(
        onPressed: () => p.requesterType == 'driver' ? _showStripeDialog(ctx) : _showWireDialog(ctx),
        icon: Icon(p.requesterType == 'driver' ? Icons.payment_rounded : Icons.account_balance_rounded, size: 14),
        label: Text(p.requesterType == 'driver' ? 'Pay via Stripe' : 'Process & Wire', style: const TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(backgroundColor: p.requesterType == 'driver' ? const Color(0xFF6366F1) : const Color(0xFF0EA5E9), foregroundColor: Colors.white, minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 10)),
      ));
    } else if (p.status == 'processing' && p.requesterType == 'restaurant') {
      children.add(ElevatedButton.icon(
        onPressed: () => _markCompleted(),
        icon: const Icon(Icons.task_alt_rounded, size: 14),
        label: const Text('Mark Completed', style: TextStyle(fontSize: 12)),
        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF22C55E), foregroundColor: Colors.white, minimumSize: const Size(0, 30), padding: const EdgeInsets.symmetric(horizontal: 10)),
      ));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Row(mainAxisAlignment: MainAxisAlignment.end, children: children);
  }

  Future<void> _approve() async {
    setState(() => _loading = true);
    try {
      await ref.read(payoutServiceProvider).approvePayout(p.id);
      widget.onRefresh();
      if (mounted) AppSnackbar.success(context, 'Payout approved');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markCompleted() async {
    setState(() => _loading = true);
    try {
      await ref.read(payoutServiceProvider).markPayoutCompleted(payoutId: p.id);
      widget.onRefresh();
      if (mounted) AppSnackbar.success(context, 'Marked completed');
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showRejectDialog(BuildContext ctx) async {
    final ctrl = TextEditingController();
    final note = await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Reject Payout'),
        content: TextField(controller: ctrl, decoration: const InputDecoration(hintText: 'Reason for rejection (optional)', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Reject')),
        ],
      ),
    );
    if (note != null) {
      setState(() => _loading = true);
      try {
        await ref.read(payoutServiceProvider).rejectPayout(p.id, note.isNotEmpty ? note : 'Rejected by admin');
        widget.onRefresh();
        if (mounted) AppSnackbar.success(context, 'Payout rejected');
      } catch (e) {
        if (mounted) AppSnackbar.error(context, friendlyError(e));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _showStripeDialog(BuildContext ctx) async {
    final amount = '${AppConstants.currencySymbol}${NumberFormat('#,##0.00').format(p.amount)}';
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.payment_rounded, color: Color(0xFF6366F1)), SizedBox(width: 8), Text('Stripe Payout')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Send payment via Stripe:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bank: ${p.bankName}', style: const TextStyle(fontSize: 13)),
                  Text('Account: ${p.bankAccountNumber}', style: const TextStyle(fontSize: 13)),
                  Text('Holder: ${p.bankAccountHolder}', style: const TextStyle(fontSize: 13)),
                  Text('Amount: $amount', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6366F1), foregroundColor: Colors.white), child: const Text('Send via Stripe')),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _loading = true);
      try {
        await ref.read(payoutServiceProvider).processPayout(p.id);
        widget.onRefresh();
        if (mounted) AppSnackbar.success(context, 'Stripe payout initiated');
      } catch (e) {
        if (mounted) AppSnackbar.error(context, friendlyError(e));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  Future<void> _showWireDialog(BuildContext ctx) async {
    final amount = '${AppConstants.currencySymbol}${NumberFormat('#,##0.00').format(p.amount)}';
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.account_balance_rounded, color: Color(0xFF0EA5E9)), SizedBox(width: 8), Text('Wire Transfer')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Bank: ${p.bankName}', style: const TextStyle(fontSize: 13)),
                  if (p.bankBranch != null) Text('Branch: ${p.bankBranch}', style: const TextStyle(fontSize: 13)),
                  Text('Account: ${p.bankAccountNumber}', style: const TextStyle(fontSize: 13)),
                  Text('Holder: ${p.bankAccountHolder}', style: const TextStyle(fontSize: 13)),
                  Text('Amount: $amount', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Text('This will mark the payout as Processing and deduct from the restaurant balance.', style: TextStyle(fontSize: 12, color: Color(0xFF6B7280))),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0EA5E9), foregroundColor: Colors.white), child: const Text('Process Wire')),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _loading = true);
      try {
        await ref.read(payoutServiceProvider).processRestaurantPayout(p.id);
        widget.onRefresh();
        if (mounted) AppSnackbar.success(context, 'Wire transfer initiated');
      } catch (e) {
        if (mounted) AppSnackbar.error(context, friendlyError(e));
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  String _mask(String acc) {
    if (acc.length <= 4) return acc;
    return '${'*' * (acc.length - 4)}${acc.substring(acc.length - 4)}';
  }
}
