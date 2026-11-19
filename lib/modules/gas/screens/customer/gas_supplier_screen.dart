import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/auth_user/address_provider.dart';
import '../../../../providers/auth_user/auth_provider.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import 'gas_orders_screen.dart';

/// Browse a supplier's cylinders, choose exchange vs new, and place an order.
class GasSupplierScreen extends ConsumerStatefulWidget {
  const GasSupplierScreen({super.key, required this.supplier});
  final GasSupplier supplier;

  @override
  ConsumerState<GasSupplierScreen> createState() => _GasSupplierScreenState();
}

class _GasSupplierScreenState extends ConsumerState<GasSupplierScreen> {
  final List<GasCartLine> _cart = [];
  bool _placing = false;
  String? _error;

  int get _subtotal => _cart.fold(0, (s, l) => s + l.unitCents * l.qty);
  int get _deposits => _cart.fold(0, (s, l) => s + l.depositCents);

  void _addLine(GasProduct p, String type) {
    setState(() {
      final existing = _cart.where((l) => l.product.id == p.id && l.purchaseType == type);
      if (existing.isNotEmpty) {
        existing.first.qty += 1;
      } else {
        _cart.add(GasCartLine(product: p, purchaseType: type));
      }
    });
  }

  void _changeQty(GasCartLine l, int delta) {
    setState(() {
      l.qty += delta;
      if (l.qty <= 0) _cart.remove(l);
    });
  }

  Future<void> _placeOrder() async {
    final addr = ref.read(selectedAddressProvider);
    final user = ref.read(currentUserProvider);
    final lat = addr?.latitude ?? user?.latitude;
    final lng = addr?.longitude ?? user?.longitude;
    final addressText = addr?.address ?? user?.address ?? '';
    if (lat == null || lng == null || addressText.isEmpty) {
      setState(() => _error = 'Add a delivery address with a location first.');
      return;
    }
    // exchange lines need a declaration; default from the product if missing
    for (final l in _cart.where((l) => l.purchaseType == 'exchange')) {
      l.existingBrand ??= l.product.brand;
      l.existingSize ??= l.product.sizeLabel;
      l.condition ??= 'good';
    }
    setState(() { _placing = true; _error = null; });
    try {
      await ref.read(gasServiceProvider).placeOrder(
            supplierId: widget.supplier.id,
            lines: _cart,
            address: addressText,
            lat: lat,
            lng: lng,
          );
      if (!mounted) return;
      ref.invalidate(myGasOrdersProvider);
      Navigator.pushReplacement(context,
          MaterialPageRoute(builder: (_) => const GasOrdersScreen(justPlaced: true)));
    } catch (e) {
      setState(() => _error = _friendly('$e'));
    } finally {
      if (mounted) setState(() => _placing = false);
    }
  }

  String _friendly(String raw) {
    if (raw.contains('outside the supplier delivery area')) {
      return 'Your delivery address is outside this supplier\'s coverage area.';
    }
    if (raw.contains('insufficient stock')) return 'Sorry, that cylinder just went out of stock.';
    if (raw.contains('not available')) return 'This supplier is not accepting orders right now.';
    return raw.replaceAll('PostgrestException', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(gasProductsProvider(widget.supplier.id));
    return Scaffold(
      appBar: AppBar(title: Text(widget.supplier.businessName)),
      body: productsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load products.\n$e', textAlign: TextAlign.center)),
        data: (products) {
          if (products.isEmpty) {
            return const Center(child: Text('No cylinders listed yet.'));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 180),
            children: [for (final p in products) _ProductCard(product: p, onAdd: _addLine)],
          );
        },
      ),
      bottomSheet: _cart.isEmpty ? null : _CartBar(
        subtotal: _subtotal,
        deposits: _deposits,
        lines: _cart,
        placing: _placing,
        error: _error,
        onQty: _changeQty,
        onPlace: _placeOrder,
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onAdd});
  final GasProduct product;
  final void Function(GasProduct, String) onAdd;

  @override
  Widget build(BuildContext context) {
    final out = !product.inStock;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.propane_tank_rounded, color: Color(0xFFFF5A1F)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('${product.brand} · ${product.sizeLabel}',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                if (out)
                  const Text('Out of stock', style: TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ),
            if (product.description != null && product.description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(product.description!, style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                if (product.exchangeAvailable && product.exchangePriceCents != null)
                  Expanded(
                    child: _BuyButton(
                      label: 'Exchange',
                      price: gasMoney(product.exchangePriceCents!),
                      enabled: !out,
                      onTap: () => onAdd(product, 'exchange'),
                    ),
                  ),
                if (product.exchangeAvailable && product.newAvailable) const SizedBox(width: 10),
                if (product.newAvailable && product.newPriceCents != null)
                  Expanded(
                    child: _BuyButton(
                      label: 'New cylinder',
                      price: gasMoney(product.newPriceCents!),
                      sub: product.depositCents > 0 ? '+ ${gasMoney(product.depositCents)} deposit' : null,
                      enabled: !out,
                      onTap: () => onAdd(product, 'new'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _BuyButton extends StatelessWidget {
  const _BuyButton({required this.label, required this.price, this.sub, required this.enabled, required this.onTap});
  final String label;
  final String price;
  final String? sub;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: enabled ? onTap : null,
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          Text(price, style: const TextStyle(fontSize: 13)),
          if (sub != null) Text(sub!, style: const TextStyle(fontSize: 10)),
        ],
      ),
    );
  }
}

class _CartBar extends StatelessWidget {
  const _CartBar({
    required this.subtotal, required this.deposits, required this.lines,
    required this.placing, required this.error, required this.onQty, required this.onPlace,
  });
  final int subtotal;
  final int deposits;
  final List<GasCartLine> lines;
  final bool placing;
  final String? error;
  final void Function(GasCartLine, int) onQty;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + pad),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 12)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 130),
            child: SingleChildScrollView(
              child: Column(
                children: [
                  for (final l in lines)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Expanded(child: Text('${l.product.brand} ${l.product.sizeLabel} · ${l.purchaseType}',
                              style: const TextStyle(fontSize: 13))),
                          IconButton(visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.remove_circle_outline, size: 20),
                              onPressed: () => onQty(l, -1)),
                          Text('${l.qty}'),
                          IconButton(visualDensity: VisualDensity.compact,
                              icon: const Icon(Icons.add_circle_outline, size: 20),
                              onPressed: () => onQty(l, 1)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 10),
          _row('Subtotal', gasMoney(subtotal)),
          if (deposits > 0) _row('Refundable deposit', gasMoney(deposits)),
          Text('Delivery & service fees are added at the next step.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          if (error != null) Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(backgroundColor: const Color(0xFFFF5A1F)),
              onPressed: placing ? null : onPlace,
              child: placing
                  ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Place gas order'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String a, String b) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [Text(a), Text(b, style: const TextStyle(fontWeight: FontWeight.w600))]),
      );
}
