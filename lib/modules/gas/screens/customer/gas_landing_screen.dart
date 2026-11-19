import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/gas_models.dart';
import '../../providers/gas_providers.dart';
import 'gas_supplier_screen.dart';
import 'gas_orders_screen.dart';

/// Cooking Gas landing — lists verified, operational LPG suppliers.
class GasLandingScreen extends ConsumerWidget {
  const GasLandingScreen({super.key});

  static const _orange = Color(0xFFFF5A1F);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suppliersAsync = ref.watch(gasLiveSuppliersProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cooking Gas'),
        actions: [
          IconButton(
            tooltip: 'My gas orders',
            icon: const Icon(Icons.receipt_long_rounded),
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const GasOrdersScreen())),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(gasLiveSuppliersProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            const _Header(),
            const SizedBox(height: 16),
            suppliersAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => _ErrorBox(message: '$e'),
              data: (suppliers) {
                if (suppliers.isEmpty) return const _EmptyState();
                return Column(
                  children: [
                    for (final s in suppliers)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _SupplierCard(supplier: s),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            const _SafetyNote(),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5A1F), Color(0xFFD7263D)],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text('Cooking Gas Delivery',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                SizedBox(height: 4),
                Text('Order cooking gas from approved suppliers and have it delivered to your doorstep.',
                    style: TextStyle(color: Colors.white, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier});
  final GasSupplier supplier;

  @override
  Widget build(BuildContext context) {
    final open = supplier.isOpen;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: open
            ? () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => GasSupplierScreen(supplier: supplier)))
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 48, height: 48,
                decoration: BoxDecoration(
                  color: GasLandingScreen._orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: supplier.logoUrl != null && supplier.logoUrl!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(supplier.logoUrl!, fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => const Icon(
                                Icons.propane_tank_rounded, color: GasLandingScreen._orange)),
                      )
                    : const Icon(Icons.propane_tank_rounded, color: GasLandingScreen._orange),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supplier.businessName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                    if (supplier.approvedBrands.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(supplier.approvedBrands.join(' · '),
                          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                    ],
                    const SizedBox(height: 4),
                    Text(open ? 'Open · delivering now' : 'Currently closed',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: open ? const Color(0xFF059669) : Theme.of(context).hintColor)),
                  ],
                ),
              ),
              if (open) const Icon(Icons.chevron_right_rounded),
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
        padding: const EdgeInsets.only(top: 56),
        child: Column(
          children: [
            Icon(Icons.local_fire_department_outlined, size: 56, color: Theme.of(context).hintColor),
            const SizedBox(height: 12),
            const Text('No gas suppliers available yet',
                style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Check back soon — suppliers appear here once approved.',
                textAlign: TextAlign.center, style: TextStyle(color: Theme.of(context).hintColor)),
          ],
        ),
      );
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 24),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('Could not load suppliers.\n$message',
            style: const TextStyle(color: Colors.red)),
      );
}

class _SafetyNote extends StatelessWidget {
  const _SafetyNote();
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.shield_outlined, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Safety: if you ever suspect a gas leak, move away from the hazard, avoid '
                'any ignition source, and contact your supplier or emergency services. '
                'HotBite personnel do not install, connect, repair or refill LPG equipment.',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
              ),
            ),
          ],
        ),
      );
}
