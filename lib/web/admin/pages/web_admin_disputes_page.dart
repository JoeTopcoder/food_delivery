import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../config/app_constants.dart';
import '../../../models/refund_model.dart';
import '../../../providers/feature_providers.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

class WebAdminDisputesPage extends ConsumerStatefulWidget {
  const WebAdminDisputesPage({super.key});

  @override
  ConsumerState<WebAdminDisputesPage> createState() => _WebAdminDisputesPageState();
}

class _WebAdminDisputesPageState extends ConsumerState<WebAdminDisputesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Disputes & Refunds', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Review refund requests and resolve disputes', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: () {
                  ref.invalidate(allRefundsProvider);
                  ref.invalidate(allDisputesProvider);
                },
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── Tabs ─────────────────────────────────────────────────
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
                  labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  tabs: const [
                    Tab(text: 'Refund Requests'),
                    Tab(text: 'Disputes'),
                  ],
                ),
                const Divider(height: 1),
                SizedBox(
                  height: 600,
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: const [
                      _RefundsTab(),
                      _DisputesTab(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Refunds Tab ───────────────────────────────────────────────────────────────

class _RefundsTab extends ConsumerWidget {
  const _RefundsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refundsAsync = ref.watch(allRefundsProvider);
    return refundsAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allRefundsProvider)),
      data: (refunds) {
        if (refunds.isEmpty) {
          return const AppEmptyState(icon: Icons.receipt_long_rounded, title: 'No refund requests');
        }
        return Column(
          children: [
            // Table header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: const Color(0xFFF8FAFC),
              child: const Row(children: [
                SizedBox(width: 120, child: Text('ORDER', style: _h)),
                SizedBox(width: 100, child: Text('AMOUNT', style: _h)),
                SizedBox(width: 90, child: Text('STATUS', style: _h)),
                SizedBox(width: 200, child: Text('REASON', style: _h)),
                SizedBox(width: 140, child: Text('DATE', style: _h)),
                Expanded(child: Text('ACTIONS', style: _h, textAlign: TextAlign.right)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: refunds.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (_, i) => _RefundRow(refund: refunds[i], onAction: () => ref.invalidate(allRefundsProvider)),
              ),
            ),
          ],
        );
      },
    );
  }

  static const _h = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5);
}

class _RefundRow extends ConsumerWidget {
  final Refund refund;
  final VoidCallback onAction;
  const _RefundRow({required this.refund, required this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPending = refund.status == 'pending';
    final color = _statusColor(refund.status);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          SizedBox(width: 120, child: Text('…${refund.orderId.substring(refund.orderId.length > 8 ? refund.orderId.length - 8 : 0)}', style: const TextStyle(fontSize: 13, fontFamily: 'monospace', color: Color(0xFF374151)))),
          SizedBox(width: 100, child: Text('${AppConstants.currencySymbol}${refund.amount.toStringAsFixed(2)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF10B981)))),
          SizedBox(
            width: 90,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(refund.status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
            ),
          ),
          SizedBox(width: 200, child: Text(refund.reason, style: const TextStyle(fontSize: 12, color: Color(0xFF374151)), maxLines: 2, overflow: TextOverflow.ellipsis)),
          SizedBox(width: 140, child: Text(DateFormat('MMM d, y').format(refund.createdAt), style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)))),
          Expanded(
            child: isPending
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => _update(context, ref, 'rejected'),
                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red), padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32)),
                        child: const Text('Reject', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: () => _update(context, ref, 'approved'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12), minimumSize: const Size(0, 32)),
                        child: const Text('Approve', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _update(BuildContext ctx, WidgetRef ref, String status) async {
    await ref.read(refundServiceProvider).updateRefundStatus(refundId: refund.id, status: status);
    onAction();
    if (ctx.mounted) AppSnackbar.success(ctx, 'Refund $status');
  }

  static Color _statusColor(String s) {
    switch (s) {
      case 'approved': return const Color(0xFF10B981);
      case 'rejected': return Colors.red;
      case 'processed': return const Color(0xFF3B82F6);
      default: return const Color(0xFFF59E0B);
    }
  }
}

// ── Disputes Tab ──────────────────────────────────────────────────────────────

class _DisputesTab extends ConsumerWidget {
  const _DisputesTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputesAsync = ref.watch(allDisputesProvider);
    return disputesAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(allDisputesProvider)),
      data: (disputes) {
        if (disputes.isEmpty) {
          return const AppEmptyState(icon: Icons.gavel_rounded, title: 'No disputes filed');
        }
        return Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              color: const Color(0xFFF8FAFC),
              child: const Row(children: [
                SizedBox(width: 90, child: Text('STATUS', style: _h)),
                SizedBox(width: 120, child: Text('TYPE', style: _h)),
                SizedBox(width: 120, child: Text('ORDER', style: _h)),
                Expanded(child: Text('DESCRIPTION', style: _h)),
                SizedBox(width: 100, child: Text('ACTIONS', style: _h, textAlign: TextAlign.right)),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: disputes.length,
                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                itemBuilder: (_, i) => _DisputeRow(dispute: disputes[i], onAction: () => ref.invalidate(allDisputesProvider)),
              ),
            ),
          ],
        );
      },
    );
  }

  static const _h = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5);
}

class _DisputeRow extends ConsumerWidget {
  final Dispute dispute;
  final VoidCallback onAction;
  const _DisputeRow({required this.dispute, required this.onAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = dispute.status == 'open';
    final color = isOpen ? const Color(0xFFF59E0B) : dispute.status == 'resolved' ? const Color(0xFF10B981) : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(20)),
              child: Text(dispute.status.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: color)),
            ),
          ),
          SizedBox(width: 120, child: Text(dispute.typeLabel, style: const TextStyle(fontSize: 12, color: Color(0xFF374151)))),
          SizedBox(width: 120, child: Text('…${dispute.orderId.substring(dispute.orderId.length > 8 ? dispute.orderId.length - 8 : 0)}', style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: Color(0xFF9CA3AF)))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(dispute.description, style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)), maxLines: 2, overflow: TextOverflow.ellipsis),
                if (dispute.resolution != null)
                  Text('Resolved: ${dispute.resolution}', style: const TextStyle(fontSize: 11, color: Color(0xFF10B981), fontStyle: FontStyle.italic)),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: isOpen
                ? Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.gavel, size: 14),
                      label: const Text('Resolve', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF004E89), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10), minimumSize: const Size(0, 32)),
                      onPressed: () => _showResolve(context, ref),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Future<void> _showResolve(BuildContext ctx, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: ctx,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Resolve Dispute'),
        content: TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'Enter resolution details…', border: OutlineInputBorder())),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Resolve')),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      await ref.read(refundServiceProvider).resolveDispute(disputeId: dispute.id, resolution: result, resolvedBy: 'admin');
      onAction();
      if (ctx.mounted) AppSnackbar.success(ctx, 'Dispute resolved');
    }
  }
}
