import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import '../../widgets/gas_ui.dart';
import 'gas_supplier_screen.dart';
import 'gas_orders_screen.dart';

/// Cooking Gas landing — hero + verified, operational LPG suppliers.
class GasLandingScreen extends ConsumerWidget {
  const GasLandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(gasLiveSuppliersProvider);
    return Scaffold(
      appBar: GasBrand.appBar(context, actions: [
        IconButton(
          tooltip: 'My gas orders',
          icon: const Icon(Icons.receipt_long_rounded),
          onPressed: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => const GasOrdersScreen())),
        ),
      ]),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(gasLiveSuppliersProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            const Text('Cooking Gas',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, letterSpacing: -0.5)),
            const SizedBox(height: 14),
            const _HeroCard(),
            const SizedBox(height: 20),
            const Text('Choose a Supplier',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            suppliersAsync.when(
              loading: () => const Padding(
                  padding: EdgeInsets.only(top: 40), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => _ErrorBox(message: '$e'),
              data: (suppliers) {
                if (suppliers.isEmpty) return const _EmptyState();
                return Column(children: [
                  for (final s in suppliers)
                    Padding(padding: const EdgeInsets.only(bottom: 12), child: _SupplierCard(supplier: s)),
                ]);
              },
            ),
            const SizedBox(height: 8),
            const _SafetyNote(),
          ],
        ),
      ),
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
      child: Stack(
        children: [
          Positioned(
            right: -6, top: -4, bottom: -4,
            child: Icon(Icons.propane_tank_rounded, size: 120, color: Colors.white.withValues(alpha: 0.22)),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text('Cooking Gas\nDelivered to Your Door',
                  style: TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900, height: 1.1)),
              SizedBox(height: 14),
              _HeroBullet(icon: Icons.verified_rounded, text: 'Order from trusted suppliers'),
              SizedBox(height: 8),
              _HeroBullet(icon: Icons.swap_horiz_rounded, text: 'Exchange or get a new cylinder'),
              SizedBox(height: 8),
              _HeroBullet(icon: Icons.local_shipping_rounded, text: 'Fast and reliable delivery'),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroBullet extends StatelessWidget {
  const _HeroBullet({required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Text(text, style: const TextStyle(color: Colors.white, fontSize: 13.5, fontWeight: FontWeight.w500)),
      ]);
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier});
  final GasSupplier supplier;

  @override
  Widget build(BuildContext context) {
    final open = supplier.isOpen;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1.5,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: open
            ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => GasSupplierScreen(supplier: supplier)))
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              GasBrand.flameAvatar(logoUrl: supplier.logoUrl),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supplier.businessName,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5)),
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
                    Row(children: [
                      Icon(Icons.circle, size: 9, color: open ? GasBrand.green : Theme.of(context).hintColor),
                      const SizedBox(width: 5),
                      Text(open ? 'Open · Delivering now' : 'Currently closed',
                          style: TextStyle(
                              fontSize: 12.5, fontWeight: FontWeight.w600,
                              color: open ? GasBrand.green : Theme.of(context).hintColor)),
                    ]),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: Theme.of(context).hintColor),
            ],
          ),
        ),
      ),
    );
  }
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

class _SafetyNote extends StatelessWidget {
  const _SafetyNote();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.shield_outlined, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Safety Notice', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13)),
              const SizedBox(height: 3),
              Text(
                'If you suspect a gas leak, move away from the hazard, avoid any ignition source, '
                'and contact your supplier or emergency services. HotBite personnel do not install, '
                'connect, repair or refill LPG equipment.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor, height: 1.3),
              ),
            ]),
          ),
        ]),
      );
}
