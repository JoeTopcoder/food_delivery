import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/gas_ui.dart';

/// My Gas Orders — filter chips + status badges + itemized totals (mockup design).
class GasOrdersScreen extends ConsumerStatefulWidget {
  const GasOrdersScreen({super.key, this.justPlaced = false, this.paid = true});
  final bool justPlaced;
  final bool paid;
  @override
  ConsumerState<GasOrdersScreen> createState() => _GasOrdersScreenState();
}

class _GasOrdersScreenState extends ConsumerState<GasOrdersScreen> {
  static const _filters = ['All', 'Pending', 'Completed', 'Cancelled'];
  String _filter = 'All';

  String _bucket(GasOrder o) {
    switch (o.status) {
      case 'delivered':
      case 'exchange_completed':
      case 'completed':
        return 'Completed';
      case 'cancelled':
      case 'rejected':
      case 'refunded':
      case 'failed_delivery':
        return 'Cancelled';
      default:
        return 'Pending';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ordersAsync = ref.watch(myGasOrdersProvider);
    return Scaffold(
      appBar: GasBrand.appBar(context),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('My Gas Orders',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            ),
          ),
          if (widget.justPlaced)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (widget.paid ? GasBrand.green : GasBrand.orange).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.paid
                    ? 'Order placed and paid. The supplier will confirm and prepare your cylinder.'
                    : 'Order placed — payment didn\'t go through. Top up your wallet and pay below.',
                style: TextStyle(color: widget.paid ? GasBrand.greenDark : const Color(0xFFC2410C), fontWeight: FontWeight.w600),
              ),
            ),
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final f = _filters[i];
                final sel = _filter == f;
                return ChoiceChip(
                  label: Text(f),
                  selected: sel,
                  showCheckmark: false,
                  selectedColor: GasBrand.orange,
                  labelStyle: TextStyle(
                      color: sel ? Colors.white : Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700),
                  onSelected: (_) => setState(() => _filter = f),
                );
              },
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => ref.refresh(myGasOrdersProvider.future),
              child: ordersAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load orders.\n$e'))]),
                data: (orders) {
                  final list = _filter == 'All' ? orders : orders.where((o) => _bucket(o) == _filter).toList();
                  if (list.isEmpty) {
                    return ListView(children: const [SizedBox(height: 120), Center(child: Text('No orders here.'))]);
                  }
                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _OrderCard(order: list[i], bucket: _bucket(list[i])),
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
  const _OrderCard({required this.order, required this.bucket});
  final GasOrder order;
  final String bucket;
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
          const SnackBar(content: Text('Payment successful — your cylinder is being prepared.')));
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

  ({String label, Color color}) get _badge {
    final o = widget.order;
    if (widget.bucket == 'Completed') return (label: 'Completed', color: GasBrand.green);
    if (widget.bucket == 'Cancelled') {
      return (label: o.status == 'refunded' ? 'Refunded' : (o.status == 'rejected' ? 'Rejected' : 'Cancelled'), color: Colors.red);
    }
    // Pending bucket
    if (o.status == 'pending_supplier' || o.status == 'awaiting_payment') {
      return (label: 'Pending', color: const Color(0xFF2563EB));
    }
    if (o.status == 'out_for_delivery' || o.status == 'assigned') {
      return (label: 'On the way', color: GasBrand.green);
    }
    return (label: 'Confirmed', color: GasBrand.green);
  }

  String get _dateLabel {
    final d = widget.order.placedAt?.toLocal();
    if (d == null) return '';
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ap = d.hour < 12 ? 'AM' : 'PM';
    return '${months[d.month - 1]} ${d.day}, ${d.year} · $h:${d.minute.toString().padLeft(2, '0')} $ap';
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final badge = _badge;
    final canCancel = o.status == 'pending_supplier' || o.status == 'supplier_accepted' || o.status == 'awaiting_payment';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(color: GasBrand.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.propane_tank_rounded, color: GasBrand.orange, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Order #${o.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                  if (_dateLabel.isNotEmpty)
                    Text(_dateLabel, style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: badge.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(badge.label, style: TextStyle(color: badge.color, fontSize: 11.5, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _row('Items', gasMoney(o.itemsCents)),
          if (o.depositCents > 0) _row('Deposit', gasMoney(o.depositCents)),
          _row('Delivery', gasMoney(o.deliveryCents)),
          if (o.serviceFeeCents > 0) _row('Service fee', gasMoney(o.serviceFeeCents)),
          const Divider(height: 16),
          _row('Total', gasMoney(o.totalCents), bold: true),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
          if (o.paymentStatus == 'unpaid' && !o.isTerminal) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity, height: 46,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: GasBrand.orange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                onPressed: _busy ? null : _payWallet,
                icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
                label: Text(_busy ? 'Processing…' : 'Pay ${gasMoney(o.totalCents)} from wallet'),
              ),
            ),
          ],
          if (canCancel)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(onPressed: _busy ? null : _cancel,
                  child: const Text('Cancel order', style: TextStyle(color: Colors.red))),
            ),
        ],
      ),
    );
  }

  Widget _row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400,
              fontSize: bold ? 15 : 13.5, color: bold ? null : Theme.of(context).hintColor)),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600, fontSize: bold ? 15 : 13.5)),
        ]),
      );
}
