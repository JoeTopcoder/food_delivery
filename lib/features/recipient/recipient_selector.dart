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
///
/// With no students linked it collapses to a single line. A radio group whose
/// only option is "Myself" asks a question that has no second answer, and it
/// was costing every customer a screenful of checkout to say nothing.
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

    if (students.isEmpty) {
      // Nothing to choose between yet — offer the way in, and no more.
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => showAddStudentDialog(context, ref),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.person_add_alt, size: 16),
          label: const Text(
            'Ordering for a student? Add them',
            style: TextStyle(fontSize: 12.5),
          ),
        ),
      );
    }

    void select(String? id) {
      if (ref.read(selectedStudentProvider) == id) return;
      ref.read(selectedStudentProvider.notifier).state = id;
      onChanged?.call();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header and the add action share one row rather than stacking two.
        Row(
          children: [
            Text(
              'Who is this for?',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: () => showAddStudentDialog(context, ref),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.person_add_alt, size: 15),
              label: const Text('Add', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
        const SizedBox(height: 6),
        _RecipientTile(
          title: 'Myself',
          selected: selectedId == null,
          onTap: () => select(null),
        ),
        ...students.map(
          (s) => _RecipientTile(
            title: s.name,
            subtitle: s.hasSchool
                ? '${s.schoolName} · ${AppConstants.currencySymbol}'
                      '${AppConstants.studentDeliveryFee.toStringAsFixed(0)}'
                : 'No school on file',
            warning: !s.hasSchool,
            selected: selectedId == s.id,
            onTap: () => select(s.id),
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

/// Where a student order is actually going. Replaces the checkout's own address
/// card rather than sitting above it — both were printing the same street.
class SchoolDestinationBanner extends ConsumerWidget {
  const SchoolDestinationBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final student = ref.watch(selectedStudentDetailProvider);
    if (student == null || !student.hasSchool) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.primaryColor.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.school_outlined, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.schoolName!,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
                Text(
                  student.schoolAddress!,
                  style: TextStyle(
                    fontSize: 11.5,
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
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.warning = false,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final bool warning;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.primaryColor.withValues(alpha: 0.12)
              : scheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppTheme.primaryColor : scheme.outlineVariant,
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked,
              size: 17,
              color: selected ? AppTheme.primaryColor : scheme.outline,
            ),
            const SizedBox(width: 9),
            // Name and detail on one line: two stacked lines per option was
            // most of what made this block a screenful.
            Expanded(
              child: Text.rich(
                TextSpan(
                  text: title,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: scheme.onSurface,
                  ),
                  children: subtitle == null
                      ? null
                      : [
                          TextSpan(
                            text: '  $subtitle',
                            style: TextStyle(
                              fontWeight: FontWeight.w400,
                              fontSize: 11.5,
                              color: warning
                                  ? Colors.orange.shade400
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
