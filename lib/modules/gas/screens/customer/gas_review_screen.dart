import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../config/app_constants.dart';
import '../../../../models/money/saved_card_model.dart';
import '../../../../providers/auth_user/address_provider.dart';
import '../../../../providers/auth_user/auth_provider.dart';
import '../../../../providers/money/payment_provider.dart';
import '../../../../providers/money/wallet_provider.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/gas_ui.dart';
import 'gas_order_success_screen.dart';

/// Delivery & payment review — the selected cylinder, address, price summary,
/// and payment choice (wallet/card/cash). "Place Gas Order" creates + pays.
class GasReviewScreen extends ConsumerStatefulWidget {
  const GasReviewScreen({super.key, required this.supplier, required this.line});
  final GasSupplier supplier;
  final GasCartLine line;
  @override
  ConsumerState<GasReviewScreen> createState() => _GasReviewScreenState();
}

class _GasReviewScreenState extends ConsumerState<GasReviewScreen> {
  late int _qty = widget.line.qty;
  String _method = 'wallet';
  SavedCard? _card;
  bool _busy = false;
  String? _error;

  GasCartLine get _line => widget.line..qty = _qty;

  ({double? lat, double? lng, String addr}) get _dest {
    final a = ref.read(selectedAddressProvider);
    final u = ref.read(currentUserProvider);
    return (lat: a?.latitude ?? u?.latitude, lng: a?.longitude ?? u?.longitude, addr: a?.address ?? u?.address ?? '');
  }

  Future<void> _place() async {
    final d = _dest;
    if (d.lat == null || d.lng == null || d.addr.isEmpty) {
      setState(() => _error = 'Add a delivery address with a location first.');
      return;
    }
    if (_method == 'stripe' && _card?.stripePaymentMethodId == null) {
      setState(() => _error = 'Select a verified card, or choose Wallet / Cash.');
      return;
    }
    setState(() { _busy = true; _error = null; });
    try {
      final svc = ref.read(gasServiceProvider);
      final orderId = await svc.placeOrder(
          supplierId: widget.supplier.id, lines: [_line], address: d.addr, lat: d.lat!, lng: d.lng!);
      if (_method == 'wallet') {
        await svc.payFromWallet(orderId);
      } else if (_method == 'stripe') {
        await svc.payByCard(orderId, _card!.stripePaymentMethodId!);
      } else {
        await svc.setCashOnDelivery(orderId);
      }
      if (!mounted) return;
      ref.invalidate(myGasOrdersProvider);
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => GasOrderSuccessScreen(supplierName: widget.supplier.businessName, method: _method),
      ));
    } catch (e) {
      setState(() => _error = _friendly('$e'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendly(String raw) {
    if (raw.contains('outside the supplier delivery area')) return 'Your address is outside this supplier\'s coverage area.';
    if (raw.contains('insufficient stock')) return 'That cylinder just went out of stock.';
    if (raw.contains('insufficient wallet')) return 'Not enough wallet balance — choose another method or top up.';
    if (raw.contains('FunctionException') || raw.contains('404') || raw.contains('not configured') || raw.contains('Failed to send')) {
      return 'Card payment isn\'t available yet — please use Wallet or Cash on Delivery.';
    }
    return raw.replaceAll('PostgrestException', '').replaceAll('Exception:', '').trim();
  }

  @override
  Widget build(BuildContext context) {
    final d = _dest;
    final uid = ref.watch(currentUserIdProvider);
    final savedCardsAsync = uid == null ? null : ref.watch(savedCardsProvider(uid));
    final line = _line;
    return Scaffold(
      appBar: GasBrand.appBar(context),
      body: Stack(children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 170),
          children: [
            const Text('Cooking Gas', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 14),
            // Supplier
            _card_(context, child: Row(children: [
              GasBrand.flameAvatar(size: 46, logoUrl: widget.supplier.logoUrl),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.supplier.businessName, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
                Row(children: [
                  const Icon(Icons.star_rounded, color: Color(0xFFFBBF24), size: 15),
                  Text(' ${widget.supplier.rating.toStringAsFixed(1)}  ·  ', style: const TextStyle(fontSize: 12.5)),
                  const Text('Open · Delivering now', style: TextStyle(color: GasBrand.greenDark, fontSize: 12.5, fontWeight: FontWeight.w600)),
                ]),
              ])),
            ])),
            const SizedBox(height: 14),
            const Text('Selected Cylinder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _card_(context, highlight: true, child: Row(children: [
              GasBrand.cylinderTile(brand: line.product.brand, size: 56, imageUrl: line.product.imageUrl),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${line.product.brand} – ${line.product.sizeLabel}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(line.purchaseType == 'exchange' ? 'Exchange Cylinder' : 'New Cylinder',
                    style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor)),
                Text(gasMoney(line.unitCents), style: const TextStyle(color: GasBrand.orange, fontWeight: FontWeight.w900, fontSize: 15)),
              ])),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(foregroundColor: GasBrand.orange, side: const BorderSide(color: GasBrand.orange)),
                icon: const Icon(Icons.swap_horiz_rounded, size: 16),
                label: const Text('Change'),
              ),
            ])),
            const SizedBox(height: 14),
            // Quantity
            Row(children: [
              const Text('Quantity', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
              const Spacer(),
              _QtyBtn(icon: Icons.remove_rounded, onTap: () => setState(() => _qty = (_qty - 1).clamp(1, 99))),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('$_qty', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
              _QtyBtn(icon: Icons.add_rounded, onTap: () => setState(() => _qty = (_qty + 1).clamp(1, 99))),
            ]),
            const SizedBox(height: 14),
            // Delivery address
            _card_(context, child: Row(children: [
              const Icon(Icons.location_on_rounded, color: GasBrand.orange),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Delivery Address', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                Text(d.addr.isEmpty ? 'No address set — add one in your profile' : d.addr,
                    style: TextStyle(fontSize: 12.5, color: Theme.of(context).hintColor)),
              ])),
            ])),
            const SizedBox(height: 14),
            // Price summary
            const Text('Price Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _PriceSummary(supplierId: widget.supplier.id, line: line, lat: d.lat, lng: d.lng),
            const SizedBox(height: 16),
            const Text('Payment Method', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Consumer(builder: (context, ref, _) {
              final bal = ref.watch(walletBalanceStreamProvider).valueOrNull?.availableBalance ?? 0;
              return _PayTile(icon: Icons.account_balance_wallet_rounded, label: 'Wallet',
                  subtitle: bal > 0 ? 'Balance: ${AppConstants.currencySymbol}${bal.toStringAsFixed(2)}' : 'No funds — top up in your profile',
                  selected: _method == 'wallet', onTap: () => setState(() => _method = 'wallet'));
            }),
            const SizedBox(height: 8),
            _PayTile(icon: Icons.credit_card_rounded, label: 'Credit / Debit Card', subtitle: 'Visa, Mastercard, and more',
                selected: _method == 'stripe', onTap: () => setState(() => _method = 'stripe')),
            if (_method == 'stripe' && savedCardsAsync != null)
              savedCardsAsync.when(
                loading: () => const Padding(padding: EdgeInsets.all(10), child: LinearProgressIndicator()),
                error: (_, __) => const SizedBox.shrink(),
                data: (cards) {
                  final v = cards.where((c) => c.isVerified).toList();
                  _card ??= v.isNotEmpty ? v.first : null;
                  if (v.isEmpty) {
                    return const Padding(padding: EdgeInsets.fromLTRB(10, 6, 10, 0),
                        child: Text('No verified card on file. Add one in your profile, or use wallet/cash.',
                            style: TextStyle(fontSize: 12, color: Colors.redAccent)));
                  }
                  return Column(children: [
                    for (final c in v)
                      InkWell(onTap: () => setState(() => _card = c), borderRadius: BorderRadius.circular(10),
                        child: Padding(padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6), child: Row(children: [
                          Icon(_card?.id == c.id ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                              size: 20, color: _card?.id == c.id ? GasBrand.orange : Theme.of(context).hintColor),
                          const SizedBox(width: 10),
                          Text('${c.cardBrand} •••• ${c.lastFour}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
                        ])),
                      ),
                  ]);
                },
              ),
            const SizedBox(height: 8),
            _PayTile(icon: Icons.payments_rounded, label: 'Cash on Delivery', subtitle: 'Pay with cash when your order arrives',
                selected: _method == 'cash', onTap: () => setState(() => _method = 'cash')),
          ],
        ),
        Align(alignment: Alignment.bottomCenter, child: _PlaceBar(
          supplierId: widget.supplier.id, line: line, lat: d.lat, lng: d.lng,
          method: _method, busy: _busy, error: _error, onPlace: _place,
        )),
      ]),
    );
  }

  Widget _card_(BuildContext context, {required Widget child, bool highlight = false}) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: highlight ? Border.all(color: GasBrand.orange, width: 1.6) : null,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: child,
      );
}

class _PriceSummary extends ConsumerWidget {
  const _PriceSummary({required this.supplierId, required this.line, required this.lat, required this.lng});
  final String supplierId;
  final GasCartLine line;
  final double? lat;
  final double? lng;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget wrap(Widget c) => Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 3))],
          ),
          child: c,
        );
    if (lat == null || lng == null) {
      return wrap(_row(context, 'Items', gasMoney(line.lineCents), bold: true));
    }
    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(gasServiceProvider).quote(supplierId: supplierId, lines: [line], lat: lat!, lng: lng!),
      builder: (context, snap) {
        final q = snap.data;
        int c(String k) => (q?[k] as num?)?.toInt() ?? 0;
        return wrap(Column(children: [
          _row(context, 'Items (${line.product.brand} – ${line.product.sizeLabel} ${line.purchaseType})', gasMoney(c('items_cents'))),
          if (c('deposit_cents') > 0) _row(context, 'Refundable deposit', gasMoney(c('deposit_cents'))),
          _row(context, 'Delivery Fee', q == null ? '…' : gasMoney(c('delivery_cents'))),
          _row(context, 'Service Fee', q == null ? '…' : gasMoney(c('service_fee_cents'))),
          const Divider(height: 16),
          _row(context, 'Total', q == null ? '…' : gasMoney(c('total_cents')), bold: true),
        ]));
      },
    );
  }

  Widget _row(BuildContext c, String a, String b, {bool bold = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2.5),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(child: Text(a, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w400,
              fontSize: bold ? 16 : 13, color: bold ? null : Theme.of(c).hintColor))),
          Text(b, style: TextStyle(fontWeight: bold ? FontWeight.w900 : FontWeight.w600,
              fontSize: bold ? 17 : 13, color: bold ? GasBrand.orange : null)),
        ]),
      );
}

class _PayTile extends StatelessWidget {
  const _PayTile({required this.icon, required this.label, required this.subtitle, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected ? GasBrand.orange.withValues(alpha: 0.08) : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? GasBrand.orange : Theme.of(context).dividerColor.withValues(alpha: 0.4), width: selected ? 1.6 : 1),
          ),
          child: Row(children: [
            Icon(icon, color: selected ? GasBrand.orange : Theme.of(context).hintColor),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5)),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
            ])),
            Icon(selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
                color: selected ? GasBrand.orange : Theme.of(context).hintColor),
          ]),
        ),
      );
}

class _PlaceBar extends ConsumerWidget {
  const _PlaceBar({required this.supplierId, required this.line, required this.lat, required this.lng, required this.method, required this.busy, required this.error, required this.onPlace});
  final String supplierId;
  final GasCartLine line;
  final double? lat;
  final double? lng;
  final String method;
  final bool busy;
  final String? error;
  final VoidCallback onPlace;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pad = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 10 + pad),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 16, offset: const Offset(0, -4))],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8),
            child: Text(error!, style: const TextStyle(color: Colors.red, fontSize: 12.5))),
        SizedBox(
          width: double.infinity, height: 52,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: GasBrand.orange,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
            onPressed: busy ? null : onPlace,
            icon: busy
                ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.shopping_cart_rounded),
            label: Text(busy ? 'Placing…' : 'Place Gas Order', style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w800)),
          ),
        ),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.shield_outlined, size: 14, color: GasBrand.red),
          const SizedBox(width: 5),
          Text('Safe & Reliable Delivery', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: GasBrand.red)),
        ]),
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
        color: Colors.transparent,
        shape: CircleBorder(side: BorderSide(color: Theme.of(context).dividerColor)),
        child: InkWell(customBorder: const CircleBorder(), onTap: onTap,
            child: Padding(padding: const EdgeInsets.all(6), child: Icon(icon, size: 20))),
      );
}
