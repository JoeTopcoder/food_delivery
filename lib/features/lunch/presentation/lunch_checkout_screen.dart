import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_constants.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../data/lunch_cart_provider.dart';
import '../data/lunch_service.dart';

/// Checkout: the one place that asks who the lunch is for.
///
/// Every recipient change re-quotes against the server rather than adjusting a
/// number locally, because the delivery fee and the destination school are
/// decided by the same code that will place the order. What the parent reads
/// here is therefore what they will be charged — not the app's guess at it.
class LunchCheckoutScreen extends ConsumerStatefulWidget {
  const LunchCheckoutScreen({super.key});

  @override
  ConsumerState<LunchCheckoutScreen> createState() =>
      _LunchCheckoutScreenState();
}

class _LunchCheckoutScreenState extends ConsumerState<LunchCheckoutScreen> {
  /// null = ordering for myself, which is the default every time.
  String? _studentId;
  final _instructions = TextEditingController();

  LunchQuote? _quote;
  bool _quoting = true;
  bool _placing = false;
  String? _quoteError;

  @override
  void initState() {
    super.initState();
    _requote();
  }

  @override
  void dispose() {
    _instructions.dispose();
    super.dispose();
  }

  Future<void> _requote() async {
    final items = ref.read(lunchCartProvider.notifier).toOrderItems();
    if (items.isEmpty) return;
    setState(() {
      _quoting = true;
      _quoteError = null;
    });
    try {
      final q = await ref
          .read(lunchServiceProvider)
          .quote(items: items, studentId: _studentId);
      if (!mounted) return;
      setState(() {
        _quote = q;
        _quoting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _quoting = false;
        _quoteError = friendlyError(e);
      });
    }
  }

  void _selectRecipient(String? studentId) {
    if (_studentId == studentId) return;
    setState(() => _studentId = studentId);
    _requote();
  }

  Future<void> _linkStudent() async {
    final controller = TextEditingController();
    final walletId = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a student'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the wallet ID from your child’s own account. '
              'They can find it on their profile screen.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Wallet ID',
                hintText: 'e.g. 7A3F21',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: const Text('Link'),
          ),
        ],
      ),
    );
    if (walletId == null || walletId.isEmpty || !mounted) return;

    try {
      final name = await ref.read(lunchServiceProvider).linkStudent(walletId);
      if (!mounted) return;
      ref.invalidate(myStudentsProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$name linked to your account')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyError(e)),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  Future<void> _placeOrder(List<LinkedStudent> students) async {
    // A student with no school on file has nowhere to deliver to. The server
    // rejects this too; catching it here means the parent hears about it
    // before they commit rather than after.
    if (_studentId != null) {
      LinkedStudent? student;
      for (final s in students) {
        if (s.id == _studentId) student = s;
      }
      if (student != null && !student.hasSchool) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${student.name} has no school on file yet, so lunch '
              'cannot be delivered to them.',
            ),
            backgroundColor: Colors.red.shade700,
          ),
        );
        return;
      }
    }

    setState(() => _placing = true);
    try {
      final result = await ref
          .read(lunchServiceProvider)
          .placeOrder(
            items: ref.read(lunchCartProvider.notifier).toOrderItems(),
            studentId: _studentId,
            instructions: _instructions.text.trim().isEmpty
                ? null
                : _instructions.text.trim(),
          );
      if (!mounted) return;
      // The cart is cleared only after the server has accepted the order, so a
      // failure never costs the parent the basket they just built.
      ref.read(lunchCartProvider.notifier).clear();
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Text('Lunch ordered'),
          content: Text(
            result['recipient_type'] == 'student'
                ? 'Delivering to ${result['school_name'] ?? 'the school'}.'
                : 'Delivering to your address.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.of(context)
        ..pop() // checkout
        ..pop(); // cart
    } catch (e) {
      if (!mounted) return;
      setState(() => _placing = false);
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
    final studentsAsync = ref.watch(myStudentsProvider);
    final lines = ref.watch(lunchCartProvider);
    final scheme = Theme.of(context).colorScheme;
    final c = AppConstants.currencySymbol;
    final students = studentsAsync.valueOrNull ?? const <LinkedStudent>[];
    LinkedStudent? selected;
    for (final s in students) {
      if (s.id == _studentId) selected = s;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Lunch Checkout')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          Text(
            'Who is this lunch for?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          _RecipientTile(
            title: 'Myself',
            subtitle: 'Delivered to your address',
            selected: _studentId == null,
            onTap: () => _selectRecipient(null),
          ),
          ...students.map(
            (s) => _RecipientTile(
              title: s.name,
              subtitle: s.hasSchool
                  ? '${s.schoolName}'
                  : 'No school on file — cannot deliver yet',
              warning: !s.hasSchool,
              selected: _studentId == s.id,
              onTap: () => _selectRecipient(s.id),
            ),
          ),
          if (studentsAsync.isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ),
          const SizedBox(height: 4),
          TextButton.icon(
            onPressed: _linkStudent,
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Add a student by wallet ID'),
          ),

          // The delivery destination, shown as fact rather than as something to
          // fill in: for a student it is their school, taken from their record.
          if (selected != null && selected.hasSchool) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.primaryColor.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.school_outlined, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delivering to ${selected.schoolName}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        if (selected.schoolAddress?.isNotEmpty ?? false) ...[
                          const SizedBox(height: 2),
                          Text(
                            selected.schoolAddress!,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          Text(
            'Order',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${line.quantity} × ${line.item.name}',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ),
                  Text('$c${line.lineTotal.toStringAsFixed(0)}'),
                ],
              ),
            ),

          const SizedBox(height: 16),
          TextField(
            controller: _instructions,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Delivery instructions (optional)',
              hintText: 'e.g. leave at the front office',
              border: OutlineInputBorder(),
            ),
          ),

          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: _quoteError != null
                ? Column(
                    children: [
                      Text(
                        _quoteError!,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.red.shade400),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _requote,
                        child: const Text('Try again'),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      _summaryRow(
                        'Subtotal',
                        _quote == null
                            ? null
                            : '$c${_quote!.subtotal.toStringAsFixed(2)}',
                      ),
                      const SizedBox(height: 6),
                      _summaryRow(
                        _studentId == null
                            ? 'Delivery (to you)'
                            : 'Delivery (to school)',
                        _quote == null
                            ? null
                            : '$c${_quote!.deliveryFee.toStringAsFixed(2)}',
                      ),
                      const Divider(height: 20),
                      _summaryRow(
                        'Total',
                        _quote == null
                            ? null
                            : '$c${_quote!.total.toStringAsFixed(2)}',
                        emphasise: true,
                      ),
                    ],
                  ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
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
              onPressed:
                  (_placing || _quoting || _quote == null || lines.isEmpty)
                  ? null
                  : () => _placeOrder(students),
              child: _placing
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _quote == null
                          ? 'Calculating…'
                          : 'Place Lunch Order · '
                                '$c${_quote!.total.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String? value, {bool emphasise = false}) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontWeight: emphasise ? FontWeight.w800 : FontWeight.w500,
            fontSize: emphasise ? 16 : 14,
            color: emphasise ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
        value == null
            ? const SizedBox(
                height: 14,
                width: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                value,
                style: TextStyle(
                  fontWeight: emphasise ? FontWeight.w800 : FontWeight.w600,
                  fontSize: emphasise ? 18 : 14,
                  color: scheme.onSurface,
                ),
              ),
      ],
    );
  }
}

class _RecipientTile extends StatelessWidget {
  const _RecipientTile({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    this.warning = false,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final bool warning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 20,
              color: selected ? AppTheme.primaryColor : scheme.outline,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: warning
                          ? Colors.orange.shade400
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
