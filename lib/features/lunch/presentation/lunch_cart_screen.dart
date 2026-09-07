import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_constants.dart';
import '../../../utils/app_theme.dart';
import '../data/lunch_cart_provider.dart';
import 'lunch_checkout_screen.dart';

/// The lunch cart: items, quantities, subtotal.
///
/// No delivery fee is shown here, and that is intentional rather than an
/// omission. The fee depends on whether the lunch is for the parent or a
/// linked student, and that is not decided until checkout — quoting a figure
/// now would mean quoting one the order may not use.
class LunchCartScreen extends ConsumerWidget {
  const LunchCartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(lunchCartProvider);
    final subtotal = ref.watch(lunchSubtotalProvider);
    final scheme = Theme.of(context).colorScheme;
    final c = AppConstants.currencySymbol;

    return Scaffold(
      appBar: AppBar(title: const Text('My Lunch Cart')),
      body: lines.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.lunch_dining_outlined,
                    size: 64,
                    color: scheme.outlineVariant,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Your lunch cart is empty',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Browse lunch'),
                  ),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                for (final line in lines)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.item.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: scheme.onSurface,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '$c${line.item.price.toStringAsFixed(0)} each',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _QtyStepper(
                          quantity: line.quantity,
                          onChanged: (q) => ref
                              .read(lunchCartProvider.notifier)
                              .setQuantity(line.item.id, q),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 74,
                          child: Text(
                            '$c${line.lineTotal.toStringAsFixed(0)}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Subtotal',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      '$c${subtotal.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Delivery is worked out at checkout, once you choose who the '
                  'lunch is for.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
      bottomNavigationBar: lines.isEmpty
          ? null
          : SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const LunchCheckoutScreen(),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Proceed to Checkout',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded, size: 19),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({required this.quantity, required this.onChanged});

  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => onChanged(quantity - 1),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Icon(Icons.remove, size: 18),
            ),
          ),
          Text(
            '$quantity',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          InkWell(
            onTap: () => onChanged(quantity + 1),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Icon(Icons.add, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}
