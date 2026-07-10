import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/stripe/payout_request_model.dart';
import '../../providers/stripe/admin_payout_provider.dart';
import '../../widgets/stripe/payout_status_badge.dart';
import '../../widgets/stripe/money_text.dart';

class AdminPayoutRequestsScreen extends ConsumerStatefulWidget {
  const AdminPayoutRequestsScreen({super.key});

  @override
  ConsumerState<AdminPayoutRequestsScreen> createState() =>
      _AdminPayoutRequestsScreenState();
}

class _AdminPayoutRequestsScreenState
    extends ConsumerState<AdminPayoutRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;

  static const _tabStatuses = [
    'requested',
    'approved',
    'transferred',
    'processing',
    'paid',
    'failed',
    'rejected',
  ];
  static const _tabLabels = [
    'Requested',
    'Approved',
    'Transferred',
    'Processing',
    'Paid',
    'Failed',
    'Rejected',
  ];

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _tabStatuses.length, vsync: this);
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging) {
        ref
            .read(adminPayoutProvider.notifier)
            .load(status: _tabStatuses[_tabs.index]);
      }
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _approve(PayoutRequest p) async {
    final note = await _noteDialog('Approve Payout');
    if (!mounted || note == null) return;
    await ref.read(adminPayoutProvider.notifier).approve(p.id, note: note);
  }

  Future<void> _reject(PayoutRequest p) async {
    final note = await _noteDialog('Reject Payout', required: true);
    if (!mounted || note == null || note.isEmpty) return;
    await ref.read(adminPayoutProvider.notifier).reject(p.id, note: note);
  }

  Future<String?> _noteDialog(String title, {bool required = false}) async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1D2E),
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            hintText:
                required ? 'Reason (required)' : 'Note (optional)',
            hintStyle: const TextStyle(color: Colors.white38),
            filled: true,
            fillColor: const Color(0xFF0F1117),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (required && ctrl.text.trim().isEmpty) return;
              Navigator.pop(
                ctx,
                ctrl.text.trim().isEmpty ? null : ctrl.text.trim(),
              );
            },
            child: Text(title.split(' ').first),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(adminPayoutProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        title: const Text('Payout Requests'),
        backgroundColor: const Color(0xFF0F1117),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref
                .read(adminPayoutProvider.notifier)
                .load(status: _tabStatuses[_tabs.index]),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white38,
          indicatorColor: const Color(0xFF7C3AED),
          tabs: _tabLabels.map((l) => Tab(text: l)).toList(),
        ),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(state),
    );
  }

  Widget _buildBody(AdminPayoutState state) {
    if (state.error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline,
                color: Color(0xFFEF4444), size: 48),
            const SizedBox(height: 12),
            Text(state.error!,
                style: const TextStyle(color: Colors.white54),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => ref
                  .read(adminPayoutProvider.notifier)
                  .load(status: _tabStatuses[_tabs.index]),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (state.payouts.isEmpty) {
      return Center(
        child: Text(
          'No ${_tabLabels[_tabs.index].toLowerCase()} payouts',
          style: const TextStyle(color: Colors.white38, fontSize: 15),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: state.payouts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _payoutCard(state.payouts[i]),
    );
  }

  Widget _payoutCard(PayoutRequest p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
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
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${p.role.toUpperCase()} · ${p.userId.substring(0, 8)}…',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                      ),
                    ),
                    Text(
                      _formatDateTime(p.createdAt),
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                    if (p.stripeAccountId.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        'acct: ${p.stripeAccountId}',
                        style: const TextStyle(
                          color: Colors.white24,
                          fontSize: 10,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              PayoutStatusBadge(p.status),
            ],
          ),

          // Stripe IDs
          if (p.stripeTransferId != null) ...[
            const SizedBox(height: 6),
            _metaRow('Transfer', p.stripeTransferId!),
          ],
          if (p.stripePayoutId != null)
            _metaRow('Payout', p.stripePayoutId!),

          // Failure info
          if (p.failureMessage != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline,
                    color: Color(0xFFEF4444), size: 14),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    p.failureMessage!,
                    style: const TextStyle(
                        color: Color(0xFFEF4444), fontSize: 12),
                  ),
                ),
              ],
            ),
          ],

          // Admin note
          if (p.adminNote != null) ...[
            const SizedBox(height: 4),
            Text(
              'Note: ${p.adminNote}',
              style:
                  const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],

          // Action buttons
          const SizedBox(height: 12),
          Row(
            children: [
              if (p.status == PayoutStatus.requested) ...[
                _actionBtn(
                    'Approve', const Color(0xFF22C55E), () => _approve(p)),
                const SizedBox(width: 8),
                _actionBtn(
                    'Reject', const Color(0xFFEF4444), () => _reject(p)),
              ],
              if (p.status == PayoutStatus.failed ||
                  p.status == PayoutStatus.transferred ||
                  p.status == PayoutStatus.approved) ...[
                _actionBtn(
                  'Retry',
                  const Color(0xFF3B82F6),
                  () => ref
                      .read(adminPayoutProvider.notifier)
                      .retry(p.id),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _metaRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Text('$label: ',
              style:
                  const TextStyle(color: Colors.white38, fontSize: 10)),
          Expanded(
            child: Text(
              value,
              style:
                  const TextStyle(color: Colors.white54, fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    final d = dt.toLocal();
    return '${d.day}/${d.month}/${d.year} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
  }
}
