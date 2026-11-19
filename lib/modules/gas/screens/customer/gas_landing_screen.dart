import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/gas_ui.dart';
import '../../widgets/gas_bottom_nav.dart';
import 'gas_supplier_screen.dart';
import 'gas_orders_screen.dart';

/// Cooking Gas landing — hero + verified, operational LPG suppliers.
class GasLandingScreen extends ConsumerWidget {
  const GasLandingScreen({super.key, this.embedded = false});

  /// When true, this is hosted inside the main app bottom nav, so it omits its
  /// own Scaffold app bar + bottom nav (the host provides them).
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(gasLiveSuppliersProvider);
    final body = RefreshIndicator(
        onRefresh: () async => ref.refresh(gasLiveSuppliersProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            const _HeroCard(),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text('Choose a Gas Supplier',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: -0.4)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: const [
                    Icon(Icons.location_on_rounded, size: 15, color: GasBrand.orange),
                    SizedBox(width: 3),
                    Text('Kingston & St. Andrew', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 16),
                  ]),
                ),
              ],
            ),
            const SizedBox(height: 12),
            suppliersAsync.when(
              loading: () => const Padding(padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => _ErrorBox(message: '$e'),
              data: (suppliers) {
                if (suppliers.isEmpty) return const _EmptyState();
                return Column(children: [
                  for (final s in suppliers)
                    Padding(padding: const EdgeInsets.only(bottom: 14), child: _SupplierCard(supplier: s)),
                ]);
              },
            ),
          ],
        ),
    );

    if (embedded) return SafeArea(bottom: false, child: body);
    return Scaffold(
      appBar: GasBrand.appBar(context, actions: [
        IconButton(
          tooltip: 'My gas orders',
          icon: const Icon(Icons.receipt_long_rounded),
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GasOrdersScreen())),
        ),
      ]),
      bottomNavigationBar: const GasBottomNav(current: 3),
      body: body,
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: GasBrand.flameGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: GasBrand.red.withValues(alpha: 0.25), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: Stack(children: [
        Positioned(right: -8, top: -8, bottom: -8,
            child: Icon(Icons.local_fire_department_rounded, size: 120, color: Colors.white.withValues(alpha: 0.20))),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
          Text('Cooking Gas\nDelivered to Your Door',
              style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w900, height: 1.1)),
          SizedBox(height: 14),
          _HeroBullet(text: 'Order from trusted suppliers'),
          SizedBox(height: 9),
          _HeroBullet(text: 'Exchange or get a new cylinder'),
          SizedBox(height: 9),
          _HeroBullet(text: 'Fast & reliable delivery'),
        ]),
      ]),
    );
  }
}

class _HeroBullet extends StatelessWidget {
  const _HeroBullet({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.check_circle_rounded, color: Color(0xFFFBBF24), size: 19),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      ]);
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier});
  final GasSupplier supplier;

  String get _brand => supplier.approvedBrands.isNotEmpty ? supplier.approvedBrands.first : 'GasPro';

  void _open(BuildContext context) => Navigator.push(context,
      MaterialPageRoute(builder: (_) => GasSupplierScreen(supplier: supplier)));

  @override
  Widget build(BuildContext context) {
    final open = supplier.isOpen;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.07), blurRadius: 14, offset: const Offset(0, 5))],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            GasBrand.cylinderTile(brand: _brand, size: 76, imageUrl: supplier.logoUrl, radius: 14),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(supplier.businessName,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16))),
                  Icon(Icons.chevron_right_rounded, color: Theme.of(context).hintColor),
                ]),
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
                const SizedBox(height: 5),
                _OpenPill(open: open),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Row(children: [
                      Icon(Icons.schedule_rounded, size: 14, color: Theme.of(context).hintColor),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(supplier.hoursLabel ?? 'Hours vary',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                      ),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_shipping_rounded, size: 14, color: Theme.of(context).hintColor),
                    const SizedBox(width: 4),
                    Text(supplier.etaLabel ?? 'Est. soon',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5)),
                  ]),
                ]),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                onPressed: open ? () => _open(context) : null,
                style: OutlinedButton.styleFrom(
                    foregroundColor: GasBrand.orange,
                    side: const BorderSide(color: GasBrand.orange),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('View Products', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                onPressed: open ? () => _open(context) : null,
                style: FilledButton.styleFrom(
                    backgroundColor: GasBrand.orange,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                icon: const Icon(Icons.shopping_cart_rounded, size: 17),
                label: const Text('Order Gas', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

class _OpenPill extends StatelessWidget {
  const _OpenPill({required this.open});
  final bool open;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: (open ? GasBrand.green : Theme.of(context).hintColor).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.circle, size: 8, color: open ? GasBrand.green : Theme.of(context).hintColor),
          const SizedBox(width: 5),
          Text(open ? 'Open · Delivering now' : 'Currently closed',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                  color: open ? GasBrand.greenDark : Theme.of(context).hintColor)),
        ]),
      );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 48),
        child: Column(children: [
          Icon(Icons.local_fire_department_outlined, size: 56, color: Theme.of(context).hintColor),
          const SizedBox(height: 12),
          const Text('No gas suppliers available yet', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text('Check back soon — suppliers appear once approved.',
              textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
        ]),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 20),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
        child: Text('Could not load suppliers.\n$message', style: const TextStyle(color: Colors.red)),
      );
}
