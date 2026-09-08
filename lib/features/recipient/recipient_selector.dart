import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/app_constants.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import 'recipient_service.dart';

/// "Who is this for?" — the one place a customer chooses between themselves and
/// a linked student, dropped into every checkout that delivers.
///
/// Choosing a student redirects the delivery to their school and switches the
/// delivery fee to the flat student rate. Both are re-derived server-side when
/// the order is placed; what this widget shows is a preview, not the authority.
class RecipientSelector extends ConsumerWidget {
  const RecipientSelector({super.key, this.onChanged});

  /// Fired after the selection changes so the host checkout can re-price.
  final VoidCallback? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final studentsAsync = ref.watch(myStudentsProvider);
    final selectedId = ref.watch(selectedStudentProvider);
    final scheme = Theme.of(context).colorScheme;
    final students = studentsAsync.valueOrNull ?? const <LinkedStudent>[];

    void select(String? id) {
      if (ref.read(selectedStudentProvider) == id) return;
      ref.read(selectedStudentProvider.notifier).state = id;
      onChanged?.call();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.people_alt_outlined, size: 18, color: scheme.onSurface),
            const SizedBox(width: 8),
            Text(
              'Who is this for?',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        _RecipientTile(
          title: 'Myself',
          subtitle: 'Delivered to your address',
          selected: selectedId == null,
          onTap: () => select(null),
        ),
        ...students.map(
          (s) => _RecipientTile(
            title: s.name,
            subtitle: s.hasSchool
                ? '${s.schoolName} · ${AppConstants.currencySymbol}'
                      '${AppConstants.studentDeliveryFee.toStringAsFixed(0)} delivery'
                : 'No school on file — cannot deliver yet',
            warning: !s.hasSchool,
            selected: selectedId == s.id,
            onTap: () => select(s.id),
          ),
        ),
        if (studentsAsync.isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 10),
            child: Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => showAddStudentDialog(context, ref),
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Add a student by wallet ID'),
          ),
        ),
      ],
    );
  }
}

/// Prompts for a wallet ID and links that account as a student.
///
/// Lives here rather than inside the selector so the profile screen can offer
/// the same flow without a checkout in progress.
Future<void> showAddStudentDialog(BuildContext context, WidgetRef ref) async {
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
            'Enter the wallet ID from your child’s own account. They can find '
            'it on their Wallet screen, under the balance.',
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
  if (walletId == null || walletId.isEmpty || !context.mounted) return;

  try {
    final name = await ref.read(recipientServiceProvider).linkStudent(walletId);
    if (!context.mounted) return;
    ref.invalidate(myStudentsProvider);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('$name linked to your account')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(friendlyError(e)),
        backgroundColor: Colors.red.shade700,
      ),
    );
  }
}

/// The school banner shown once a student is selected: where the order is
/// actually going, stated as fact rather than offered as a field to edit.
class SchoolDestinationBanner extends ConsumerWidget {
  const SchoolDestinationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(selectedStudentDetailProvider);
    if (student == null || !student.hasSchool) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 10),
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
                  'Delivering to ${student.schoolName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(
                  student.schoolAddress!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Your own delivery address is not used for this order.',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
