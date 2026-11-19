import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/auth_user/address_provider.dart';
import '../../../../providers/auth_user/auth_provider.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/gas_ui.dart';
import 'gas_review_screen.dart';

/// A selectable cylinder option (one product × one purchase type).
class _Option {
  final GasProduct product;
  final String type; // 'exchange' | 'new'
  _Option(this.product, this.type);
  int get price => (type == 'exchange' ? product.exchangePriceCents : product.newPriceCents) ?? 0;
  String get key => '${product.id}|$type';
}

class GasSupplierScreen extends ConsumerStatefulWidget {
  const GasSupplierScreen({super.key, required this.supplier});
  final GasSupplier supplier;
  @override
  ConsumerState<GasSupplierScreen> createState() => _GasSupplierScreenState();
}

class _GasSupplierScreenState extends ConsumerState<GasSupplierScreen> {
  String _mode = 'exchange';
  String? _selKey;
  int _qty = 1;

  List<_Option> _options(List<GasProduct> products, String mode) {
    final out = <_Option>[];
    for (final p in products) {
      if (mode == 'exchange' && p.exchangeAvailable && p.exchangePriceCents != null) out.add(_Option(p, 'exchange'));
      if (mode == 'new' && p.newAvailable && p.newPriceCents != null) out.add(_Option(p, 'new'));
    }
    return out;
  }

  _Option? _selected(List<GasProduct> products) {
    for (final o in _options(products, _mode)) {
      if (o.key == _selKey) return o;
    }
    return null;
  }

  ({double? lat, double? lng}) get _origin {
    final addr = ref.read(selectedAddressProvider);
    final user = ref.read(currentUserProvider);
    return (lat: addr?.latitude ?? user?.latitude, lng: addr?.longitude ?? user?.longitude);
  }

  GasCartLine _line(_Option o) => GasCartLine(
        product: o.product, purchaseType: o.type, qty: _qty,
        existingBrand: o.product.brand, existingSize: o.product.sizeLabel, condition: 'good',
      );

  void _continue(_Option o) {
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => GasReviewScreen(supplier: widget.supplier, line: _line(o)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(gasProductsProvider(widget.supplier.id));
    return Scaffold(
      appBar: GasBrand.appBar(context),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load products.\n$e', textAlign: TextAlign.center)),
        data: (products) {
          final opts = _options(products, _mode);
          final sel = _selected(products);
          return Stack(children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 200),
              children: [
                const _Banner(),
                const SizedBox(height: 16),
                _ModeToggle(mode: _mode, onChanged: (m) => setState(() { _mode = m; _selKey = null; })),
                const SizedBox(height: 16),
                const Text('Choose Cylinder Size', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                const SizedBox(height: 10),
                if (opts.isEmpty)
                  Padding(padding: const EdgeInsets.only(top: 20),
                      child: Center(child: Text(_mode == 'new' ? 'No new cylinders offered here.' : 'No exchange cylinders listed yet.')))
                else
                  for (final o in opts)
                    _OptionRow(
                      option: o,
                      selected: _selKey == o.key,
                      onTap: o.product.inStock ? () => setState(() => _selKey = o.key) : null,
                    ),
              ],
            ),
            if (sel != null)
              Align(
                alignment: Alignment.bottomCenter,
                child: _SummaryBar(
                  supplierId: widget.supplier.id,
                  line: _line(sel),
                  origin: _origin,
                  qty: _qty,
                  onQty: (d) => setState(() => _qty = (_qty + d).clamp(1, 99)),
                  onContinue: () => _continue(sel),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner();
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(gradient: GasBrand.flameGradient, borderRadius: BorderRadius.circular(18)),
      padding: const EdgeInsets.all(18),
      child: Stack(children: [
        Positioned(right: -6, bottom: -10,
            child: Icon(Icons.local_fire_department_rounded, size: 120, color: Colors.white.withValues(alpha: 0.22))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('Cooking Gas Delivery',
              style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, height: 1.05)),
          SizedBox(height: 8),
          Text('Exchange your empty cylinder or get a new one delivered to your doorstep.',
              style: TextStyle(color: Colors.white, fontSize: 12.5, height: 1.3)),
        ]),
      ]),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.mode, required this.onChanged});
  final String mode;
  final void Function(String) onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(children: [
        _seg('exchange', Icons.swap_horiz_rounded, 'Exchange Cylinder', 'Return your empty cylinder'),
        _seg('new', Icons.add_circle_outline_rounded, 'New Cylinder', 'Get a new cylinder + deposit'),
      ]),
    );
  }

  Widget _seg(String value, IconData icon, String title, String sub) {
    return Expanded(
      child: Builder(builder: (context) {
        final active = mode == value;
        return InkWell(
          onTap: () => onChanged(value),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
            decoration: BoxDecoration(
              color: active ? GasBrand.orange : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18, color: active ? Colors.white : Theme.of(context).hintColor),
              const SizedBox(width: 8),
              Flexible(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5,
                          color: active ? Colors.white : Theme.of(context).colorScheme.onSurface)),
                  Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 9.5,
                          color: active ? Colors.white70 : Theme.of(context).hintColor)),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({required this.option, required this.selected, required this.onTap});
  final _Option option;
  final bool selected;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final p = option.product;
    final out = onTap == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: selected ? GasBrand.orange.withValues(alpha: 0.06) : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? GasBrand.orange : Theme.of(context).dividerColor.withValues(alpha: 0.4),
            width: selected ? 1.8 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(children: [
            GasBrand.cylinderTile(brand: p.brand, size: 62, imageUrl: p.imageUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${p.brand} – ${p.sizeLabel}${option.type == 'new' ? ' (New Cylinder)' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 3),
                Row(children: [
                  Icon(option.type == 'exchange' ? Icons.swap_horiz_rounded : Icons.add_circle_outline_rounded,
                      size: 14, color: Theme.of(context).hintColor),
                  const SizedBox(width: 4),
                  Text(option.type == 'exchange' ? 'Exchange' : 'New Cylinder',
                      style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor)),
                ]),
                const SizedBox(height: 4),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(gasMoney(option.price),
                      style: const TextStyle(color: GasBrand.orange, fontWeight: FontWeight.w900, fontSize: 17)),
                  if (option.type == 'new' && p.depositCents > 0)
                    Padding(padding: const EdgeInsets.only(left: 6, bottom: 2),
                        child: Text('+ ${gasMoney(p.depositCents)} deposit',
                            style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor))),
                ]),
              ]),
            ),
            if (out)
              const Text('Out', style: TextStyle(color: Colors.red, fontSize: 12))
            else
              Icon(selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                  color: selected ? GasBrand.orange : Theme.of(context).hintColor),
          ]),
        ),
      ),
    );
  }
}

class _SummaryBar extends ConsumerWidget {
  const _SummaryBar({required this.supplierId, required this.line, required this.origin, required this.qty, required this.onQty, required this.onContinue});
  final String supplierId;
  final GasCartLine line;
  final ({double? lat, double? lng}) origin;
  final int qty;
  final void Function(int) onQty;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + pad),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, -4))],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          const Spacer(),
          _QtyBtn(icon: Icons.remove_rounded, onTap: () => onQty(-1)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('$qty', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
          _QtyBtn(icon: Icons.add_rounded, onTap: () => onQty(1)),
        ]),
        const SizedBox(height: 10),
        _QuoteSummary(supplierId: supplierId, line: line, origin: origin),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity, height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: GasBrand.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: onContinue,
            icon: const Icon(Icons.local_shipping_rounded),
            label: const Text('Continue to Delivery', style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

/// Live price summary from the server quote (items/delivery/service/total).
class _QuoteSummary extends ConsumerWidget {
  const _QuoteSummary({required this.supplierId, required this.line, required this.origin});
  final String supplierId;
  final GasCartLine line;
  final ({double? lat, double? lng}) origin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (origin.lat == null || origin.lng == null) {
      return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        const Text('Subtotal', style: TextStyle(fontWeight: FontWeight.w700)),
        Text(gasMoney(line.lineCents), style: const TextStyle(fontWeight: FontWeight.w800)),
      ]);
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(gasServiceProvider).quote(
          supplierId: supplierId, lines: [line], lat: origin.lat!, lng: origin.lng!),
      builder: (context, snap) {
        final q = snap.data;
        int c(String k) => (q?[k] as num?)?.toInt() ?? 0;
        return Column(children: [
          _row(context, 'Cylinder (${line.product.sizeLabel} ${line.purchaseType})', gasMoney(c('items_cents'))),
          if (c('deposit_cents') > 0) _row(context, 'Deposit', gasMoney(c('deposit_cents'))),
          _row(context, 'Delivery Fee', q == null ? '…' : gasMoney(c('delivery_cents'))),
          _row(context, 'Service Fee', q == null ? '…' : gasMoney(c('service_fee_cents'))),
          const Divider(height: 14),
          _row(context, 'Total', q == null ? '…' : gasMoney(c('total_cents')), bold: true),
          if (q != null && q['in_zone'] == false)
            const Padding(padding: EdgeInsets.only(top: 4),
                child: Text('Address may be outside this supplier\'s delivery area.',
                    style: TextStyle(color: Colors.red, fontSize: 11.5))),
        ]);
      },
    );
  }

  Widget _row(BuildContext c, String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w400,
              fontSize: bold ? 16 : 13, color: bold ? null : Theme.of(c).hintColor)),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              fontSize: bold ? 17 : 13, color: bold ? GasBrand.orange : null)),
        ]),
      );
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        shape: CircleBorder(side: BorderSide(color: Theme.of(context).dividerColor)),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 20))),
      );
}
