import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/refund_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/feature_providers.dart';
import '../../utils/friendly_error.dart';

class RefundDisputeScreen extends ConsumerStatefulWidget {
  final String? orderId;
  final double? orderTotal;
  const RefundDisputeScreen({super.key, this.orderId, this.orderTotal});

  @override
  ConsumerState<RefundDisputeScreen> createState() =>
      _RefundDisputeScreenState();
}

class _RefundDisputeScreenState extends ConsumerState<RefundDisputeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

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
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Refunds & Disputes',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: AppTheme.textPrimary,
        bottom: TabBar(
          controller: _tabCtrl,
          indicatorColor: AppTheme.primaryColor,
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textSecondary,
          tabs: const [
            Tab(text: 'Refunds'),
            Tab(text: 'Disputes'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppTheme.primaryColor,
        onPressed: () => _showNewRequestSheet(context, userId),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('New Request', style: TextStyle(color: Colors.white)),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _RefundsList(userId: userId),
          _DisputesList(userId: userId),
        ],
      ),
    );
  }

  void _showNewRequestSheet(BuildContext context, String userId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NewRequestSheet(
        userId: userId,
        orderId: widget.orderId,
        orderTotal: widget.orderTotal,
        onSubmitted: () {
          ref.invalidate(userRefundsProvider(userId));
          ref.invalidate(userDisputesProvider(userId));
        },
      ),
    );
  }
}

// ── Refunds List ────────────────────────────────────────────

class _RefundsList extends ConsumerWidget {
  final String userId;
  const _RefundsList({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refundsAsync = ref.watch(userRefundsProvider(userId));
    return refundsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (refunds) {
        if (refunds.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.receipt_long, size: 48, color: Color(0xFFD1D5DB)),
                SizedBox(height: 8),
                Text(
                  'No refund requests',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Your refund history will appear here',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: refunds.length,
          itemBuilder: (_, i) => _RefundCard(refund: refunds[i]),
        );
      },
    );
  }
}

class _RefundCard extends StatelessWidget {
  final Refund refund;
  const _RefundCard({required this.refund});

  Color get _statusColor {
    switch (refund.status) {
      case 'approved':
      case 'processed':
        return const Color(0xFF10B981);
      case 'rejected':
        return Colors.red;
      default:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    refund.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _statusColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMM d, y').format(refund.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'JMD\$${refund.amount.toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              refund.reason,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280)),
            ),
            if (refund.adminNotes != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.admin_panel_settings,
                      size: 14,
                      color: Color(0xFF6366F1),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        refund.adminNotes!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Disputes List ───────────────────────────────────────────

class _DisputesList extends ConsumerWidget {
  final String userId;
  const _DisputesList({required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disputesAsync = ref.watch(userDisputesProvider(userId));
    return disputesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text(friendlyError(e))),
      data: (disputes) {
        if (disputes.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.gavel, size: 48, color: Color(0xFFD1D5DB)),
                SizedBox(height: 8),
                Text(
                  'No disputes',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Your dispute history will appear here',
                  style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: disputes.length,
          itemBuilder: (_, i) => _DisputeCard(dispute: disputes[i]),
        );
      },
    );
  }
}

class _DisputeCard extends StatelessWidget {
  final Dispute dispute;
  const _DisputeCard({required this.dispute});

  Color get _statusColor {
    switch (dispute.status) {
      case 'resolved':
      case 'closed':
        return const Color(0xFF10B981);
      case 'investigating':
        return const Color(0xFF6366F1);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
                    color: _statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    dispute.status.toUpperCase(),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: _statusColor,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    dispute.typeLabel,
                    style: const TextStyle(fontSize: 10),
                  ),
                ),
                const Spacer(),
                Text(
                  DateFormat('MMM d, y').format(dispute.createdAt),
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              dispute.description,
              style: const TextStyle(fontSize: 13),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            if (dispute.resolution != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 14,
                      color: Color(0xFF10B981),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        dispute.resolution!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── New Request Sheet ───────────────────────────────────────

class _NewRequestSheet extends ConsumerStatefulWidget {
  final String userId;
  final String? orderId;
  final double? orderTotal;
  final VoidCallback onSubmitted;

  const _NewRequestSheet({
    required this.userId,
    this.orderId,
    this.orderTotal,
    required this.onSubmitted,
  });

  @override
  ConsumerState<_NewRequestSheet> createState() => _NewRequestSheetState();
}

class _NewRequestSheetState extends ConsumerState<_NewRequestSheet> {
  bool _isRefund = true;
  final _orderIdCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _amountCtrl = TextEditingController();
  String _disputeType = 'missing_item';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.orderId != null) _orderIdCtrl.text = widget.orderId!;
    if (widget.orderTotal != null) {
      _amountCtrl.text = widget.orderTotal!.toStringAsFixed(0);
    }
  }

  @override
  void dispose() {
    _orderIdCtrl.dispose();
    _reasonCtrl.dispose();
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_orderIdCtrl.text.isEmpty || _reasonCtrl.text.isEmpty) return;
    setState(() => _loading = true);

    final service = ref.read(refundServiceProvider);
    if (_isRefund) {
      final amount = double.tryParse(_amountCtrl.text) ?? 0;
      if (amount <= 0) {
        setState(() => _loading = false);
        return;
      }
      await service.requestRefund(
        orderId: _orderIdCtrl.text,
        userId: widget.userId,
        amount: amount,
        reason: _reasonCtrl.text,
      );
    } else {
      await service.fileDispute(
        orderId: _orderIdCtrl.text,
        userId: widget.userId,
        type: _disputeType,
        description: _reasonCtrl.text,
      );
    }

    widget.onSubmitted();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'New Request',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            // Toggle
            Row(
              children: [
                _ToggleChip(
                  label: 'Refund',
                  selected: _isRefund,
                  onTap: () => setState(() => _isRefund = true),
                ),
                const SizedBox(width: 8),
                _ToggleChip(
                  label: 'Dispute',
                  selected: !_isRefund,
                  onTap: () => setState(() => _isRefund = false),
                ),
              ],
            ),
            const SizedBox(height: 12),

            TextField(
              controller: _orderIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Order ID',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),

            if (_isRefund) ...[
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Refund Amount (JMD\$)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
            ] else ...[
              DropdownButtonFormField<String>(
                initialValue: _disputeType,
                decoration: const InputDecoration(
                  labelText: 'Dispute Type',
                  border: OutlineInputBorder(),
                ),
                items: Dispute.disputeTypes
                    .map(
                      (t) => DropdownMenuItem(
                        value: t,
                        child: Text(t.replaceAll('_', ' ').toUpperCase()),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => _disputeType = v!),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _reasonCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: _isRefund
                    ? 'Reason for refund'
                    : 'Describe the issue',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
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
                        'Submit',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : const Color(0xFF6B7280),
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
