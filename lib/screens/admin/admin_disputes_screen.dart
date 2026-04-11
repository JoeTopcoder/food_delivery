import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../providers/feature_providers.dart';
import '../../models/refund_model.dart';
import '../../utils/friendly_error.dart';

class AdminDisputesScreen extends ConsumerStatefulWidget {
  const AdminDisputesScreen({super.key});

  @override
  ConsumerState<AdminDisputesScreen> createState() =>
      _AdminDisputesScreenState();
}

class _AdminDisputesScreenState extends ConsumerState<AdminDisputesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          'Disputes & Refunds',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF004E89),
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Refund Requests'),
            Tab(text: 'Disputes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: const [_AdminRefundsList(), _AdminDisputesList()],
      ),
    );
  }
}

// ── Refunds Tab ─────────────────────────────────────────────

class _AdminRefundsList extends ConsumerWidget {
  const _AdminRefundsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refundsAsync = ref.watch(allRefundsProvider);
    return refundsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (refunds) {
        if (refunds.isEmpty) {
          return const Center(child: Text('No refund requests'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: refunds.length,
          itemBuilder: (_, i) => _AdminRefundCard(refund: refunds[i]),
        );
      },
    );
  }
}

class _AdminRefundCard extends ConsumerWidget {
  final Refund refund;
  const _AdminRefundCard({required this.refund});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPending = refund.status == 'pending';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(refund.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    refund.status.toUpperCase(),
                    style: TextStyle(
                      color: _statusColor(refund.status),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '\$ ${refund.amount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Order: ${refund.orderId.substring(0, 8)}...',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            const SizedBox(height: 4),
            Text(refund.reason, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              DateFormat.yMMMd().add_jm().format(refund.createdAt),
              style: const TextStyle(fontSize: 11, color: Color(0xFF9CA3AF)),
            ),
            if (isPending) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _updateStatus(context, ref, 'rejected'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _updateStatus(context, ref, 'approved'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                      ),
                      child: const Text(
                        'Approve',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return const Color(0xFF10B981);
      case 'rejected':
        return Colors.red;
      case 'processed':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFFFFA630);
    }
  }

  Future<void> _updateStatus(
    BuildContext ctx,
    WidgetRef ref,
    String status,
  ) async {
    final service = ref.read(refundServiceProvider);
    await service.updateRefundStatus(refundId: refund.id, status: status);
    ref.invalidate(allRefundsProvider);
    if (ctx.mounted) {
      ScaffoldMessenger.of(
        ctx,
      ).showSnackBar(SnackBar(content: Text('Refund $status')));
    }
  }
}

// ── Disputes Tab ────────────────────────────────────────────

class _AdminDisputesList extends ConsumerWidget {
  const _AdminDisputesList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputesAsync = ref.watch(allDisputesProvider);
    return disputesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (disputes) {
        if (disputes.isEmpty) {
          return const Center(child: Text('No disputes filed'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: disputes.length,
          itemBuilder: (_, i) => _AdminDisputeCard(dispute: disputes[i]),
        );
      },
    );
  }
}

class _AdminDisputeCard extends ConsumerWidget {
  final Dispute dispute;
  const _AdminDisputeCard({required this.dispute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOpen = dispute.status == 'open';
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _statusColor(dispute.status).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    dispute.status.toUpperCase(),
                    style: TextStyle(
                      color: _statusColor(dispute.status),
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6B7280).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    dispute.typeLabel,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(dispute.description, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 4),
            Text(
              'Order: ${dispute.orderId.substring(0, 8)}...',
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
            if (dispute.resolution != null) ...[
              const Divider(height: 16),
              Text(
                'Resolution: ${dispute.resolution}',
                style: const TextStyle(
                  fontSize: 12,
                  fontStyle: FontStyle.italic,
                  color: Color(0xFF10B981),
                ),
              ),
            ],
            if (isOpen) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.gavel, size: 16),
                  label: const Text(
                    'Resolve',
                    style: TextStyle(color: Colors.white),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF004E89),
                  ),
                  onPressed: () => _showResolveDialog(context, ref),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'resolved':
        return const Color(0xFF10B981);
      case 'escalated':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFFFFA630);
    }
  }

  Future<void> _showResolveDialog(BuildContext ctx, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: ctx,
      builder: (dCtx) => AlertDialog(
        title: const Text('Resolve Dispute'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Enter resolution details...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dCtx, ctrl.text.trim()),
            child: const Text('Resolve'),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) {
      final service = ref.read(refundServiceProvider);
      await service.resolveDispute(
        disputeId: dispute.id,
        resolution: result,
        resolvedBy: 'admin',
      );
      ref.invalidate(allDisputesProvider);
      if (ctx.mounted) {
        ScaffoldMessenger.of(
          ctx,
        ).showSnackBar(const SnackBar(content: Text('Dispute resolved')));
      }
    }
  }
}
