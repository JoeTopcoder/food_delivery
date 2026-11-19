import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../providers/auth_user/address_provider.dart';
import '../../../../providers/auth_user/auth_provider.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/gas_ui.dart';
import 'gas_checkout_screen.dart';

/// Supplier detail — pick a cylinder option (exchange/new), quantity, and
/// place & pay (upfront). Matches the HotBite gas mockup design.
class GasSupplierScreen extends ConsumerStatefulWidget {
  const GasSupplierScreen({super.key, required this.supplier});
  final GasSupplier supplier;
  @override
  ConsumerState<GasSupplierScreen> createState() => _GasSupplierScreenState();
}

class _GasSupplierScreenState extends ConsumerState<GasSupplierScreen> {
  String? _selProductId;
  String _selType = 'exchange';
  int _qty = 1;
  bool _placing = false;
  String? _error;

  GasProduct? _selected(List<GasProduct> products) {
    for (final p in products) {
      if (p.id == _selProductId) return p;
    }
    return null;
  }

  int _unitCents(GasProduct p) =>
      (_selType == 'exchange' ? p.exchangePriceCents : p.newPriceCents) ?? 0;
  int _depositCents(GasProduct p) => _selType == 'new' ? p.depositCents * _qty : 0;
  int _total(GasProduct p) => _unitCents(p) * _qty + _depositCents(p);

  void _select(GasProduct p, String type) {
    setState(() {
      _selProductId = p.id;
      _selType = type;
      _error = null;
    });
  }

  Future<void> _place(GasProduct p) async {
    final addr = ref.read(selectedAddressProvider);
    final user = ref.read(currentUserProvider);
    final lat = addr?.latitude ?? user?.latitude;
    final lng = addr?.longitude ?? user?.longitude;
    final addressText = addr?.address ?? user?.address ?? '';
    if (lat == null || lng == null || addressText.isEmpty) {
      setState(() => _error = 'Add a delivery address with a location first.');
      return;
    }
    final line = GasCartLine(
      product: p,
      purchaseType: _selType,
      qty: _qty,
      existingBrand: p.brand,
      existingSize: p.sizeLabel,
      condition: 'good',
    );
    setState(() { _placing = true; _error = null; });
    try {
      final svc = ref.read(gasServiceProvider);
      final orderId = await svc.placeOrder(
        supplierId: widget.supplier.id,
        lines: [line],
        address: addressText,
        lat: lat,
        lng: lng,
      );
      if (!mounted) return;
      ref.invalidate(myGasOrdersProvider);
      // Go to checkout to choose wallet / card / cash.
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GasCheckoutScreen(orderId: orderId, supplierName: widget.supplier.businessName),
        ),
      );
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
    if (raw.contains('insufficient wallet')) return 'Not enough wallet balance — top up and try again.';
    if (raw.contains('not available')) return 'This supplier is not accepting orders right now.';
    return raw.replaceAll('PostgrestException', '').trim();
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
          final sel = _selected(products);
          return Stack(
            children: [
              ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 160),
                children: [
                  _BannerAndInfo(supplier: widget.supplier),
                  const SizedBox(height: 18),
                  const Text('Select Cylinder Option',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 10),
                  if (products.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 24),
                        child: Center(child: Text('No cylinders listed yet.')))
                  else
                    for (final p in products)
                      _OptionCard(
                        product: p,
                        selected: _selProductId == p.id,
                        selectedType: _selProductId == p.id ? _selType : null,
                        onSelect: (type) => _select(p, type),
                      ),
                ],
              ),
              if (sel != null)
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _CheckoutBar(
                    product: sel,
                    qty: _qty,
                    total: _total(sel),
                    placing: _placing,
                    error: _error,
                    onQty: (d) => setState(() => _qty = (_qty + d).clamp(1, 99)),
                    onPlace: () => _place(sel),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _BannerAndInfo extends StatelessWidget {
  const _BannerAndInfo({required this.supplier});
  final GasSupplier supplier;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Banner
        ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Container(
            height: 150,
            width: double.infinity,
            decoration: const BoxDecoration(gradient: GasBrand.flameGradient),
            child: supplier.bannerUrl != null && supplier.bannerUrl!.isNotEmpty
                ? Image.network(supplier.bannerUrl!, fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _bannerFallback())
                : _bannerFallback(),
          ),
        ),
        // Info card overlapping
        Transform.translate(
          offset: const Offset(0, -28),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 16, offset: const Offset(0, 6))],
            ),
            child: Column(
              children: [
                Row(children: [
                  GasBrand.flameAvatar(size: 48, logoUrl: supplier.logoUrl),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(supplier.businessName,
                            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Row(children: [
                          const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 16),
                          const SizedBox(width: 3),
                          Text(supplier.rating > 0 ? supplier.rating.toStringAsFixed(1) : 'New',
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                          if (supplier.totalOrders > 0)
                            Text('  (${supplier.totalOrders}+ orders)',
                                style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12.5)),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          const Icon(Icons.circle, size: 9, color: GasBrand.green),
                          const SizedBox(width: 5),
                          Text(supplier.isOpen ? 'Open · Delivering now' : 'Currently closed',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: GasBrand.green)),
                        ]),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  _InfoChip(icon: Icons.location_on_rounded, label: _area(supplier)),
                  _InfoChip(icon: Icons.schedule_rounded, label: supplier.hoursLabel ?? 'Hours vary'),
                  _InfoChip(icon: Icons.local_shipping_rounded, label: supplier.etaLabel ?? 'Est. soon'),
                ]),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _area(GasSupplier s) {
    final a = s.address ?? '';
    if (a.contains(',')) return a.split(',').last.trim();
    return a.isEmpty ? 'Nearby' : a;
  }

  Widget _bannerFallback() => Center(
      child: Icon(Icons.propane_tank_rounded, size: 72, color: Colors.white.withValues(alpha: 0.85)));
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(children: [
          Icon(icon, size: 18, color: GasBrand.orange),
          const SizedBox(height: 3),
          Text(label, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      );
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.product, required this.selected, required this.selectedType, required this.onSelect});
  final GasProduct product;
  final bool selected;
  final String? selectedType;
  final void Function(String type) onSelect;

  @override
  Widget build(BuildContext context) {
    final out = !product.inStock;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: selected ? GasBrand.orange : Theme.of(context).dividerColor.withValues(alpha: 0.4),
            width: selected ? 1.8 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(color: GasBrand.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.propane_tank_rounded, color: GasBrand.orange),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${product.brand} – ${product.sizeLabel}',
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                if (selected)
                  Text(selectedType == 'exchange' ? 'Exchange Cylinder' : 'New Cylinder',
                      style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor)),
              ]),
            ),
            if (out)
              const Text('Out of stock', style: TextStyle(color: Colors.red, fontSize: 12))
            else if (selected)
              const Icon(Icons.check_circle_rounded, color: GasBrand.orange)
            else
              Icon(Icons.radio_button_unchecked_rounded, color: Theme.of(context).hintColor),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            if (product.exchangeAvailable && product.exchangePriceCents != null)
              Expanded(
                child: _PriceButton(
                  label: 'Exchange',
                  price: gasMoney(product.exchangePriceCents!),
                  active: selected && selectedType == 'exchange',
                  enabled: !out,
                  onTap: () => onSelect('exchange'),
                ),
              ),
            if (product.exchangeAvailable && product.newAvailable) const SizedBox(width: 10),
            if (product.newAvailable && product.newPriceCents != null)
              Expanded(
                child: _PriceButton(
                  label: 'New Cylinder',
                  price: gasMoney(product.newPriceCents!),
                  sub: product.depositCents > 0 ? '(+ ${gasMoney(product.depositCents)} deposit)' : null,
                  active: selected && selectedType == 'new',
                  enabled: !out,
                  onTap: () => onSelect('new'),
                ),
              ),
          ]),
        ],
      ),
    );
  }
}

class _PriceButton extends StatelessWidget {
  const _PriceButton({required this.label, required this.price, this.sub, required this.active, required this.enabled, required this.onTap});
  final String label;
  final String price;
  final String? sub;
  final bool active;
  final bool enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: active ? GasBrand.orange.withValues(alpha: 0.12) : null,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? GasBrand.orange : Theme.of(context).dividerColor.withValues(alpha: 0.5)),
        ),
        child: Column(children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5,
              color: enabled ? null : Theme.of(context).disabledColor)),
          const SizedBox(height: 2),
          Text(price, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: GasBrand.orange)),
          if (sub != null) Text(sub!, style: TextStyle(fontSize: 9.5, color: Theme.of(context).hintColor)),
        ]),
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.product, required this.qty, required this.total, required this.placing, required this.error, required this.onQty, required this.onPlace});
  final GasProduct product;
  final int qty;
  final int total;
  final bool placing;
  final String? error;
  final void Function(int) onQty;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
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
          const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w700)),
          const Spacer(),
          _QtyBtn(icon: Icons.remove_rounded, onTap: () => onQty(-1)),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text('$qty', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
          _QtyBtn(icon: Icons.add_rounded, onTap: () => onQty(1)),
        ]),
        const Divider(height: 18),
        Row(children: [
          const Text('Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
          const Spacer(),
          Text(gasMoney(total), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        ]),
        Text('Delivery & service fees are added and charged to your wallet now.',
            style: TextStyle(fontSize: 10.5, color: Theme.of(context).hintColor)),
        if (error != null) Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity, height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: GasBrand.orange, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: placing ? null : onPlace,
            icon: placing
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.shopping_cart_rounded),
            label: Text(placing ? 'Placing…' : 'Place Gas Order',
                style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          ),
        ),
      ]),
    );
  }
}

class _QtyBtn extends StatelessWidget {
  const _QtyBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
        color: GasBrand.orange.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, color: GasBrand.orange, size: 20)),
        ),
      );
}
