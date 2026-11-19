import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/gas_ui.dart';
import '../../widgets/gas_bottom_nav.dart';

/// Cooking Gas Orders — hero, filter chips with counts, order cards with an
/// inline progress tracker, and LPG safety instructions (mockup design).
class GasOrdersScreen extends ConsumerStatefulWidget {
  const GasOrdersScreen({super.key, this.justPlaced = false, this.paid = true});
  final bool justPlaced;
  final bool paid;
  @override
  ConsumerState<GasOrdersScreen> createState() => _GasOrdersScreenState();
}

class _GasOrdersScreenState extends ConsumerState<GasOrdersScreen> {
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
      bottomNavigationBar: const GasBottomNav(current: 4),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(children: [Padding(padding: const EdgeInsets.all(24), child: Text('Could not load orders.\n$e'))]),
        data: (orders) {
          final counts = {
            'All': orders.length,
            'Pending': orders.where((o) => _bucket(o) == 'Pending').length,
            'Completed': orders.where((o) => _bucket(o) == 'Completed').length,
            'Cancelled': orders.where((o) => _bucket(o) == 'Cancelled').length,
          };
          final list = _filter == 'All' ? orders : orders.where((o) => _bucket(o) == _filter).toList();
          return RefreshIndicator(
            onRefresh: () async => ref.refresh(myGasOrdersProvider.future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
              children: [
                const Text('Cooking Gas Orders', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
                const SizedBox(height: 2),
                Text('Track, manage and view your cooking gas orders.',
                    style: TextStyle(fontSize: 13, color: Theme.of(context).hintColor)),
                const SizedBox(height: 14),
                const _MiniHero(),
                const SizedBox(height: 14),
                if (widget.justPlaced) _PlacedBanner(paid: widget.paid),
                _FilterChips(counts: counts, selected: _filter, onSelect: (f) => setState(() => _filter = f)),
                const SizedBox(height: 14),
                if (list.isEmpty)
                  const Padding(padding: EdgeInsets.only(top: 60), child: Center(child: Text('No orders here.')))
                else
                  for (final o in list)
                    Padding(padding: const EdgeInsets.only(bottom: 14),
                        child: _OrderCard(order: o, bucket: _bucket(o))),
                const SizedBox(height: 6),
                const _SafetyCard(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MiniHero extends StatelessWidget {
  const _MiniHero();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(gradient: GasBrand.flameGradient, borderRadius: BorderRadius.circular(16)),
        child: Stack(children: [
          Positioned(right: -6, top: -6, bottom: -6,
              child: Icon(Icons.local_fire_department_rounded, size: 80, color: Colors.white.withValues(alpha: 0.22))),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('Cooking Gas', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900)),
            SizedBox(height: 2),
            Text('Fast, Safe & Reliable Delivery', style: TextStyle(color: Colors.white, fontSize: 12.5)),
          ]),
        ]),
      );
}

class _PlacedBanner extends StatelessWidget {
  const _PlacedBanner({required this.paid});
  final bool paid;
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: (paid ? GasBrand.green : GasBrand.orange).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
        child: Text(
          paid ? 'Order placed. The supplier will confirm and prepare your cylinder.'
               : 'Order placed — pay from the order below when ready.',
          style: TextStyle(color: paid ? GasBrand.greenDark : const Color(0xFFC2410C), fontWeight: FontWeight.w600),
        ),
      );
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.counts, required this.selected, required this.onSelect});
  final Map<String, int> counts;
  final String selected;
  final void Function(String) onSelect;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          for (final f in const ['All', 'Pending', 'Completed', 'Cancelled'])
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text('$f (${counts[f] ?? 0})'),
                selected: selected == f,
                showCheckmark: false,
                selectedColor: GasBrand.orange,
                labelStyle: TextStyle(
                    color: selected == f ? Colors.white : Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w700),
                onSelected: (_) => onSelect(f),
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

  Future<void> _pay() async {
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(gasServiceProvider).payFromWallet(widget.order.id);
      if (!mounted) return;
      ref.invalidate(myGasOrdersProvider);
    } catch (e) {
      setState(() => _error = '$e'.contains('insufficient wallet') ? 'Not enough wallet balance.' : '$e'.replaceAll('PostgrestException', '').trim());
    } finally { if (mounted) setState(() => _busy = false); }
  }

  int get _stage {
    // 0 order placed, 1 supplier confirmed, 2 paid, 3 out for delivery/delivered
    final o = widget.order;
    if (o.status == 'out_for_delivery' || o.status == 'delivered' || o.status == 'exchange_completed' || o.status == 'completed') return 3;
    if (o.paymentStatus == 'paid') return 2;
    if (o.status != 'pending_supplier') return 1;
    return 0;
  }

  ({String label, Color color, IconData icon}) get _badge {
    final o = widget.order;
    if (widget.bucket == 'Completed') return (label: 'Completed', color: GasBrand.green, icon: Icons.check_circle_rounded);
    if (widget.bucket == 'Cancelled') {
      return (label: o.status == 'refunded' ? 'Refunded' : (o.status == 'rejected' ? 'Rejected' : 'Cancelled'),
          color: Colors.red, icon: Icons.cancel_rounded);
    }
    if (o.status == 'out_for_delivery' || o.status == 'assigned') return (label: 'On the way', color: GasBrand.green, icon: Icons.local_shipping_rounded);
    if (o.status == 'pending_supplier' || o.status == 'awaiting_payment') return (label: 'Pending', color: const Color(0xFF2563EB), icon: Icons.schedule_rounded);
    return (label: 'Confirmed', color: GasBrand.green, icon: Icons.check_circle_rounded);
  }

  String get _dateLabel {
    final d = widget.order.placedAt?.toLocal();
    if (d == null) return '';
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    return '${m[d.month-1]} ${d.day}, ${d.year} · $h:${d.minute.toString().padLeft(2,'0')} ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final b = _badge;
    final collapsed = widget.bucket == 'Cancelled';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GasBrand.cylinderTile(brand: 'GasPro', size: 46, radius: 10),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Order #${o.id.substring(0, 8)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
            if (_dateLabel.isNotEmpty) Text(_dateLabel, style: TextStyle(fontSize: 11.5, color: Theme.of(context).hintColor)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(color: b.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(b.icon, size: 14, color: b.color),
              const SizedBox(width: 4),
              Text(b.label, style: TextStyle(color: b.color, fontSize: 11.5, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
        if (!collapsed) ...[
          const SizedBox(height: 12),
          _row('Items', gasMoney(o.itemsCents)),
          if (o.depositCents > 0) _row('Deposit', gasMoney(o.depositCents)),
          _row('Delivery', gasMoney(o.deliveryCents)),
          if (o.serviceFeeCents > 0) _row('Service fee', gasMoney(o.serviceFeeCents)),
          const Divider(height: 14),
          _row('Total', gasMoney(o.totalCents), bold: true),
          if (widget.bucket == 'Pending') ...[
            const SizedBox(height: 14),
            _Tracker(stage: _stage),
          ],
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
          if (o.paymentStatus == 'unpaid' && !o.isTerminal) ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, height: 46, child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: GasBrand.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: _busy ? null : _pay,
              icon: const Icon(Icons.account_balance_wallet_rounded, size: 18),
              label: Text(_busy ? 'Processing…' : 'Pay ${gasMoney(o.totalCents)} from wallet'),
            )),
          ] else if (widget.bucket == 'Pending') ...[
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, height: 46, child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: GasBrand.orange, side: const BorderSide(color: GasBrand.orange),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              onPressed: () => ref.invalidate(myGasOrdersProvider),
              icon: const Icon(Icons.location_on_rounded, size: 18),
              label: const Text('Track Order', style: TextStyle(fontWeight: FontWeight.w800)),
            )),
          ],
        ],
      ]),
    );
  }

  Widget _row(String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w800 : FontWeight.w400, fontSize: bold ? 15 : 13.5,
              color: bold ? null : Theme.of(context).hintColor)),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600, fontSize: bold ? 15 : 13.5,
              color: bold ? GasBrand.orange : null)),
        ]),
      );
}

class _Tracker extends StatelessWidget {
  const _Tracker({required this.stage});
  final int stage; // 0..3
  @override
  Widget build(BuildContext context) {
    const steps = [
      ('Order\nPlaced', Icons.check_rounded),
      ('Supplier\nConfirmation', Icons.inventory_2_rounded),
      ('Make\nPayment', Icons.credit_card_rounded),
      ('Out for\nDelivery', Icons.delivery_dining_rounded),
    ];
    return Row(children: [
      for (var i = 0; i < steps.length; i++) ...[
        Column(children: [
          Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: i <= stage ? GasBrand.orange : Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(i < stage ? Icons.check_rounded : steps[i].$2,
                size: 17, color: i <= stage ? Colors.white : Theme.of(context).hintColor),
          ),
          const SizedBox(height: 4),
          Text(steps[i].$1, textAlign: TextAlign.center, maxLines: 2,
              style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600,
                  color: i <= stage ? null : Theme.of(context).hintColor)),
        ]),
        if (i < steps.length - 1)
          Expanded(child: Padding(
            padding: const EdgeInsets.only(bottom: 20),
            child: _DottedLine(active: i < stage),
          )),
      ],
    ]);
  }
}

class _DottedLine extends StatelessWidget {
  const _DottedLine({required this.active});
  final bool active;
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, cns) {
      final n = (cns.maxWidth / 7).floor().clamp(1, 20);
      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        for (var i = 0; i < n; i++)
          Container(width: 3, height: 3, decoration: BoxDecoration(
              color: active ? GasBrand.orange : Theme.of(context).dividerColor, shape: BoxShape.circle)),
      ]);
    });
  }
}

class _SafetyCard extends StatelessWidget {
  const _SafetyCard();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: GasBrand.orange.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: GasBrand.orange.withValues(alpha: 0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: const [
            Icon(Icons.shield_rounded, color: GasBrand.orange, size: 20),
            SizedBox(width: 8),
            Text('LPG Safety Instructions', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
          ]),
          const SizedBox(height: 10),
          _bullet('If you suspect a gas leak, move to a safe area immediately.'),
          _bullet('Avoid any ignition sources (flames, sparks, or electrical switches).'),
          _bullet('Contact your supplier or emergency services.'),
          _bullet('HotBite personnel do not install, connect, repair or refill LPG equipment.'),
        ]),
      );

  Widget _bullet(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 5, right: 8),
              child: Icon(Icons.circle, size: 6, color: GasBrand.orange)),
          Expanded(child: Text(t, style: const TextStyle(fontSize: 12.5, height: 1.3))),
        ]),
      );
}
