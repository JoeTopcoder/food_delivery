import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/student_verification_provider.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

/// For a student-associated order, ask the driver whether the delivery was made
/// at the registered school and record it (YES keeps benefits; NO suspends them
/// and opens a company review). Returns true if the caller should proceed with
/// the normal delivery completion, false if the driver dismissed the prompt.
///
/// For a non-student order this is a no-op that returns true.
Future<bool> ensureStudentDeliveryConfirmed(
  BuildContext context,
  WidgetRef ref,
  String orderId,
) async {
  final svc = ref.read(studentVerificationServiceProvider);
  Map<String, dynamic>? info;
  try {
    info = await svc.studentOrderInfo(orderId);
  } catch (_) {
    return true; // don't block a normal completion on a lookup hiccup
  }
  if (info == null) return true; // not a student delivery
  if (!context.mounted) return false;

  final schoolName = (info['school_name'] as String?)?.trim();
  final school = (schoolName == null || schoolName.isEmpty)
      ? 'the registered school'
      : schoolName;

  final bool? confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Student delivery confirmation'),
      content: Text('Was this delivery completed at:\n\n$school?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('No — not at school'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF067647),
            foregroundColor: Colors.white,
          ),
          child: const Text('Yes — at school'),
        ),
      ],
    ),
  );

  if (confirmed == null) return false; // dismissed → do not complete yet

  try {
    await svc.confirmDelivery(
      orderId,
      confirmed: confirmed,
      reason: confirmed ? null : 'Driver reported delivery not at the school.',
    );
  } catch (e) {
    if (context.mounted) AppSnackbar.error(context, friendlyError(e));
    return false; // couldn't record — don't complete without it
  }

  if (!confirmed && context.mounted) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Benefits suspended for review'),
        content: const Text(
          'Student benefits have been temporarily suspended because the '
          'delivery was not confirmed at the registered school. The company '
          'will review this delivery.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
  return true; // proceed with the normal completion flow
}
