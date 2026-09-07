import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_constants.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../data/lunch_cart_provider.dart';
import '../data/lunch_service.dart';
import 'lunch_cart_screen.dart';

/// Past lunch orders, with reorder.
///
/// Reorder rebuilds the CART and stops there. It deliberately does not repeat
/// the recipient: a lunch sent to one child last week should not silently go to
/// the same child today, so the choice is made again at checkout like any other
/// order.
class LunchOrdersScreen extends ConsumerWidget {
  const LunchOrdersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ordersAsync = ref.watch(lunchOrdersProvider);
    final students = ref.watch(myStudentsProvider).valueOrNull ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Lunch Orders')),
      body: ordersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(friendlyError(e), textAlign: TextAlign.center),
          ),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No lunch orders yet.'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(lunchOrdersProvider),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              itemCount: orders.length,
              itemBuilder: (context, i) => _OrderCard(
                order: orders[i],
                students: students,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _OrderCard extends ConsumerStatefulWidget {
  const _OrderCard({required this.order, required this.students});

  final LunchOrder order;
  final List<LinkedStudent> students;

  @override
  ConsumerState<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends ConsumerState<_OrderCard> {
  bool _busy = false;

  String get _recipientLabel {
    final o = widget.order;
    if (!o.isForStudent) return 'For you';
    for (final s in widget.students) {
      if (s.id == o.studentId) return 'For ${s.name}';
    }
    return 'For a student';
  }

  Future<void> _reorder() async {
    setState(() => _busy = true);
    try {
      final wanted = {for (final l in widget.order.lines) l.itemId: l.quantity};
      final items = await ref
          .read(lunchServiceProvider)
          .itemsByIds(wanted.keys.toList());
      if (!mounted) return;

      if (items.isEmpty) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('None of those items are on the menu any more.'),
          ),
        );
        return;
      }

      ref.read(lunchCartProvider.notifier).replaceWith([
        for (final item in items)
          LunchCartLine(item: item, quantity: wanted[item.id] ?? 1),
      ]);

      final missing = wanted.length - items.length;
      if (!mounted) return;
      setState(() => _busy = false);
      if (missing > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              missing == 1
                  ? '1 item is no longer available and was left out.'
                  : '$missing items are no longer available and were left out.',
            ),
          ),
        );
      }
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LunchCartScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final scheme = Theme.of(context).colorScheme;
    final c = AppConstants.currencySymbol;
    final d = o.orderedAt;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                o.isForStudent ? Icons.school_outlined : Icons.person_outline,
                size: 18,
                color: AppTheme.primaryColor,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _recipientLabel,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  o.status,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
          if (o.isForStudent && (o.schoolName?.isNotEmpty ?? false)) ...[
            const SizedBox(height: 3),
            Text(
              o.schoolName!,
              style: TextStyle(
                fontSize: 12.5,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            o.lines.map((l) => '${l.quantity} × ${l.name}').join(', '),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                '${d.day}/${d.month}/${d.year}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                '$c${o.total.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _busy ? null : _reorder,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primaryColor,
                  side: BorderSide(color: AppTheme.primaryColor),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text(
                        'Reorder',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
