import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';

/// The customer's cooking gas orders, with live status and wallet payment when
/// the supplier has accepted and the order is awaiting payment.
class GasOrdersScreen extends ConsumerWidget {
  const GasOrdersScreen({super.key, this.justPlaced = false, this.paid = true});
  final bool justPlaced;
  final bool paid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(myGasOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('My Gas Orders')),
      body: Column(
        children: [
          if (justPlaced)
            Container(
              width: double.infinity,
              color: (paid ? const Color(0xFF059669) : const Color(0xFFFF5A1F)).withValues(alpha: 0.12),
              padding: const EdgeInsets.all(12),
              child: Text(
                paid
                    ? 'Order placed and paid. The supplier will confirm and prepare your cylinder.'
                    : 'Order placed — payment didn\'t go through. Top up your wallet and pay below.',
                style: TextStyle(
                    color: paid ? const Color(0xFF047857) : const Color(0xFFC2410C),
                    fontWeight: FontWeight.w600),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.refresh(myGasOrdersProvider.future),
              child: ordersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load orders.\n$e'))]),
                data: (orders) {
                  if (orders.isEmpty) {
                    return ListView(children: const [
                      SizedBox(height: 120),
                      Center(child: Text('No gas orders yet.')),
                    ]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: orders.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _OrderCard(order: orders[i]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({required this.order});
  final GasOrder order;
  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _busy = false;
  String? _error;

  Future<void> _payWallet() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(gasServiceProvider).payFromWallet(widget.order.id);
      if (!mounted) return;
      ref.invalidate(myGasOrdersProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment successful — your cylinder is being prepared.')),
      );
    } catch (e) {
      setState(() => _error = _friendly('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(gasServiceProvider).transition(widget.order.id, 'cancelled', reason: 'customer cancelled');
      if (!mounted) return;
      ref.invalidate(myGasOrdersProvider);
    } catch (e) {
      setState(() => _error = _friendly('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(String raw) {
    if (raw.contains('insufficient wallet')) return 'Not enough wallet balance. Top up and try again.';
    return raw.replaceAll('PostgrestException', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final canCancel = !o.isTerminal &&
        (o.status == 'pending_supplier' || o.status == 'supplier_accepted' || o.status == 'awaiting_payment');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.propane_tank_rounded, color: Color(0xFFFF5A1F), size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Order #${o.id.substring(0, 8)}',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                _StatusChip(order: o),
              ],
            ),
            const SizedBox(height: 10),
            _row('Items', gasMoney(o.itemsCents)),
            if (o.depositCents > 0) _row('Refundable deposit', gasMoney(o.depositCents)),
            _row('Delivery', gasMoney(o.deliveryCents)),
            if (o.serviceFeeCents > 0) _row('Service fee', gasMoney(o.serviceFeeCents)),
            const Divider(height: 14),
            _row('Total', gasMoney(o.totalCents), bold: true),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
            if (o.paymentStatus == 'unpaid' && !o.isTerminal) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF5A1F)),
                  onPressed: _busy ? null : _payWallet,
                  icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
                  label: Text(_busy ? 'Processing…' : 'Pay ${gasMoney(o.totalCents)} from wallet'),
                ),
              ),
            ],
            if (canCancel)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _busy ? null : _cancel,
                  child: const Text('Cancel order', style: TextStyle(color: Colors.red)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w700 : FontWeight.w500)),
          ],
        ),
      );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.order});
  final GasOrder order;
  @override
  Widget build(BuildContext context) {
    Color c;
    switch (order.status) {
      case 'completed':
      case 'exchange_completed':
      case 'delivered': c = const Color(0xFF059669); break;
      case 'cancelled':
      case 'rejected':
      case 'failed_delivery': c = Colors.red; break;
      case 'awaiting_payment': c = const Color(0xFFFF5A1F); break;
      default: c = const Color(0xFF2563EB);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(order.statusLabel, style: TextStyle(color: c, fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}
