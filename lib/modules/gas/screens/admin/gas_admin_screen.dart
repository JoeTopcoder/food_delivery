import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';

/// Admin Cooking Gas operations — supplier verification + financial rollup.
class GasAdminScreen extends ConsumerWidget {
  const GasAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Cooking Gas — Admin'),
          bottom: const TabBar(tabs: [Tab(text: 'Suppliers'), Tab(text: 'Financials')]),
        ),
        body: const TabBarView(children: [_SuppliersTab(), _FinancialsTab()]),
      ),
    );
  }
}

class _SuppliersTab extends ConsumerWidget {
  const _SuppliersTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(allGasSuppliersProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(allGasSuppliersProvider.future),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e'))]),
        data: (suppliers) {
          if (suppliers.isEmpty) {
            return ListView(children: const [SizedBox(height: 120), Center(child: Text('No gas suppliers onboarded.'))]);
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: suppliers.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _AdminSupplierCard(supplier: suppliers[i]),
          );
        },
      ),
    );
  }
}

class _AdminSupplierCard extends ConsumerStatefulWidget {
  const _AdminSupplierCard({required this.supplier});
  final GasSupplier supplier;
  @override
  ConsumerState<_AdminSupplierCard> createState() => _AdminSupplierCardState();
}

class _AdminSupplierCardState extends ConsumerState<_AdminSupplierCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() a) async {
    setState(() => _busy = true);
    try {
      await a();
      ref.invalidate(allGasSuppliersProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.supplier;
    final svc = ref.read(gasServiceProvider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(s.businessName, style: const TextStyle(fontWeight: FontWeight.w700))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: (s.verificationStatus == 'approved' ? const Color(0xFF059669) : Colors.orange)
                        .withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(s.verificationStatus,
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                          color: s.verificationStatus == 'approved' ? const Color(0xFF047857) : Colors.orange.shade800)),
                ),
              ],
            ),
            if (s.address != null) Text(s.address!, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            Row(children: [
              Icon(s.deliveryOperational ? Icons.check_circle : Icons.cancel,
                  size: 14, color: s.deliveryOperational ? const Color(0xFF059669) : Colors.red),
              const SizedBox(width: 4),
              Text('Delivery ${s.deliveryOperational ? 'operational' : 'not operational'}',
                  style: const TextStyle(fontSize: 12)),
            ]),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator() else Wrap(spacing: 8, children: [
              if (s.verificationStatus != 'approved')
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF059669)),
                  onPressed: () => _run(() => svc.setSupplierStatus(s.id, 'approved')),
                  child: const Text('Approve'),
                ),
              if (s.verificationStatus == 'approved')
                OutlinedButton(
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  onPressed: () => _run(() => svc.setSupplierStatus(s.id, 'suspended')),
                  child: const Text('Suspend'),
                ),
              OutlinedButton(
                onPressed: () => _run(() => svc.setSupplierOperational(s.id, !s.deliveryOperational)),
                child: Text(s.deliveryOperational ? 'Mark not operational' : 'Mark operational'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _FinancialsTab extends ConsumerWidget {
  const _FinancialsTab();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(gasFinancialsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.refresh(gasFinancialsProvider.future),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('$e'))]),
        data: (f) {
          int c(String k) => (f[k] as num?)?.toInt() ?? 0;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text('Last 30 days', style: TextStyle(color: Theme.of(context).hintColor)),
              const SizedBox(height: 10),
              _stat('Orders (paid)', '${c('orders')}'),
              _stat('Cash collected', gasMoney(c('cash_collected_cents'))),
              const Divider(),
              _stat('Merchandise (GMV)', gasMoney(c('gmv_items_cents'))),
              _stat('Platform commission', gasMoney(c('commission_cents'))),
              _stat('Service fees', gasMoney(c('service_fee_cents'))),
              _stat('Delivery', gasMoney(c('delivery_cents'))),
              const Divider(),
              _stat('Supplier liability (owed)', gasMoney(c('supplier_liability_cents'))),
              _stat('Operator payout liability', gasMoney(c('operator_payout_liability_cents'))),
              _stat('Deposit liability (refundable)', gasMoney(c('deposits_liability_cents'))),
              const Divider(),
              _stat('Platform revenue (recognised)', gasMoney(c('platform_revenue_cents')), bold: true),
              const SizedBox(height: 16),
              Text('Deposits and unpaid payouts are liabilities, not profit.',
                  style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400)),
            Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );
}
