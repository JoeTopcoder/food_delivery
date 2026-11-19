import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import '../../services/gas_service.dart';

/// Supplier-facing gas operations. Entered from the owner/merchant dashboard.
/// The signed-in owner wears the supplier hat (see can_manage_gas_supplier()).
class GasSupplierDashboardScreen extends ConsumerWidget {
  const GasSupplierDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final supplierAsync = ref.watch(myGasSupplierProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Cooking Gas — Supplier')),
      body: supplierAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (supplier) {
          if (supplier == null) {
            return const _NotASupplier();
          }
          return _SupplierOrders(supplier: supplier);
        },
      ),
    );
  }
}

class _NotASupplier extends StatelessWidget {
  const _NotASupplier();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_fire_department_outlined, size: 56),
            const SizedBox(height: 12),
            const Text('You are not registered as a gas supplier',
                textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Contact HotBite admin to be onboarded and approved as an LPG supplier.',
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
      );
}

class _SupplierOrders extends ConsumerWidget {
  const _SupplierOrders({required this.supplier});
  final GasSupplier supplier;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(supplierGasOrdersProvider(supplier.id));
    return Column(
      children: [
        if (supplier.verificationStatus != 'approved')
          Container(
            width: double.infinity,
            color: Colors.orange.withValues(alpha: 0.15),
            padding: const EdgeInsets.all(12),
            child: Text('Supplier status: ${supplier.verificationStatus} — orders are disabled until approved.',
                style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.refresh(supplierGasOrdersProvider(supplier.id).future),
            child: ordersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e'))]),
              data: (orders) {
                if (orders.isEmpty) {
                  return ListView(children: const [SizedBox(height: 120), Center(child: Text('No gas orders yet.'))]);
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => _SupplierOrderCard(order: orders[i], supplierId: supplier.id),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _SupplierOrderCard extends ConsumerStatefulWidget {
  const _SupplierOrderCard({required this.order, required this.supplierId});
  final GasOrder order;
  final String supplierId;
  @override
  ConsumerState<_SupplierOrderCard> createState() => _SupplierOrderCardState();
}

class _SupplierOrderCardState extends ConsumerState<_SupplierOrderCard> {
  bool _busy = false;
  String? _error;

  Future<void> _do(Future<void> Function() action) async {
    setState(() { _busy = true; _error = null; });
    try {
      await action();
      if (!mounted) return;
      ref.invalidate(supplierGasOrdersProvider(widget.supplierId));
    } catch (e) {
      setState(() => _error = '$e'.replaceAll('PostgrestException', '').trim());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  GasService get _svc => ref.read(gasServiceProvider);

  Future<void> _assignOperator() async {
    final ops = await _svc.getOperators(widget.supplierId);
    if (!mounted) return;
    if (ops.isEmpty) {
      setState(() => _error = 'No eligible delivery operators. Add one first.');
      return;
    }
    final chosen = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(padding: EdgeInsets.all(14),
                child: Text('Assign authorised operator', style: TextStyle(fontWeight: FontWeight.w700))),
            for (final op in ops)
              ListTile(
                leading: const Icon(Icons.local_shipping_rounded),
                title: Text(op['name']?.toString() ?? 'Operator'),
                subtitle: Text(op['eligible'] == true ? 'Eligible' : 'Not marked eligible',
                    style: TextStyle(color: op['eligible'] == true ? const Color(0xFF059669) : Colors.red)),
                onTap: () => Navigator.pop(ctx, op),
              ),
          ],
        ),
      ),
    );
    if (chosen != null) {
      await _do(() => _svc.assignOperator(widget.order.id, chosen['id'].toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text('#${o.id.substring(0, 8)} · ${gasMoney(o.totalCents)}',
                    style: const TextStyle(fontWeight: FontWeight.w700))),
                Text(o.statusLabel, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
            if (o.deliveryAddress != null) Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(o.deliveryAddress!, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ),
            Text('Payment: ${o.paymentStatus}', style: const TextStyle(fontSize: 12)),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: _actions(o)),
          ],
        ),
      ),
    );
  }

  List<Widget> _actions(GasOrder o) {
    if (_busy) return [const Padding(padding: EdgeInsets.all(6), child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2)))];
    VoidCallback t(String s, {String? reason}) => () => _do(() => _svc.transition(o.id, s, reason: reason));
    switch (o.status) {
      case 'pending_supplier':
        return [
          _btn('Accept', t('supplier_accepted'), primary: true),
          _btn('Reject', t('rejected', reason: 'supplier rejected'), danger: true),
        ];
      case 'supplier_accepted':
        return [_btn('Start preparing', t('preparing'), primary: true)];
      case 'awaiting_payment':
      case 'payment_confirmed':
        return [_btn('Start preparing', t('preparing'), primary: true)];
      case 'preparing':
        return [_btn('Assign operator', _assignOperator, primary: true)];
      case 'assigned':
        return [_btn('Out for delivery', t('out_for_delivery'), primary: true)];
      case 'out_for_delivery':
        return [
          _btn('Mark delivered', t('delivered'), primary: true),
          _btn('Failed delivery', t('failed_delivery'), danger: true),
        ];
      case 'delivered':
        return [
          _btn('Exchange completed', t('exchange_completed')),
          _btn('Complete', t('completed'), primary: true),
        ];
      case 'exchange_completed':
        return [_btn('Complete', t('completed'), primary: true)];
      case 'failed_delivery':
        return [_btn('Reassign', t('assigned'))];
      default:
        return [];
    }
  }

  Widget _btn(String label, VoidCallback onTap, {bool primary = false, bool danger = false}) {
    if (primary) {
      return FilledButton(
        style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF5A1F),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
        onPressed: onTap, child: Text(label),
      );
    }
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
          foregroundColor: danger ? Colors.red : null,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
      onPressed: onTap, child: Text(label),
    );
  }
}
