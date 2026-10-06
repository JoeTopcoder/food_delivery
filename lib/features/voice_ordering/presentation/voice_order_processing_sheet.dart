import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../utils/app_theme.dart';
import 'controllers/voice_order_controller.dart';
import 'voice_order_confirm_screen.dart';

/// Shown right after the mic button is released — covers whatever's left
/// of [VoiceOrderStage.requestingPermission] through [resolving], a
/// clarifying question, an applied cart-editing action (remove/update
/// -quantity/clear), or an [error]. Deliberately opened only on release
/// (never while the press gesture is still in flight), so it's always safe
/// to make this freely dismissible: drag down, tap outside, back button,
/// or the explicit close button all work, at every stage. On reaching
/// [awaitingConfirmation] it hands off to the full-screen
/// [VoiceOrderConfirmScreen]; on [navigateToCart] it goes straight to
/// `/cart`. If the customer holds the button again while this is still
/// showing a question/result from a previous turn, this sheet closes
/// itself the moment a new capture actually starts.
Future<void> showVoiceOrderProcessingSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: true,
    enableDrag: true,
    backgroundColor: const Color(0xFF0D0D1A),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _VoiceOrderProcessingSheet(),
  );
}

class _VoiceOrderProcessingSheet extends ConsumerStatefulWidget {
  const _VoiceOrderProcessingSheet();

  @override
  ConsumerState<_VoiceOrderProcessingSheet> createState() => _VoiceOrderProcessingSheetState();
}

class _VoiceOrderProcessingSheetState extends ConsumerState<_VoiceOrderProcessingSheet> {
  bool _closed = false;

  void _closeOnce() {
    if (_closed || !mounted) return;
    _closed = true;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(voiceOrderControllerProvider);

    ref.listen(voiceOrderControllerProvider, (prev, next) {
      if (next.stage == VoiceOrderStage.awaitingConfirmation &&
          prev?.stage != VoiceOrderStage.awaitingConfirmation) {
        _closed = true;
        Navigator.of(context).pop();
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const VoiceOrderConfirmScreen()),
        );
        return;
      }
      if (next.stage == VoiceOrderStage.navigateToCart) {
        _closed = true;
        Navigator.of(context).pop();
        Navigator.of(context).pushNamed('/cart');
        return;
      }
      // A new press started while this sheet was still showing a result
      // from the previous turn — close it rather than stack a second one.
      final wasSettled = prev != null &&
          (prev.stage == VoiceOrderStage.error ||
              prev.stage == VoiceOrderStage.needsClarification ||
              prev.stage == VoiceOrderStage.actionApplied);
      if (wasSettled &&
          (next.stage == VoiceOrderStage.requestingPermission ||
              next.stage == VoiceOrderStage.listening)) {
        _closeOnce();
      }
    });

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Align(
              alignment: Alignment.topRight,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white54),
                onPressed: () {
                  ref.read(voiceOrderControllerProvider.notifier).retry();
                  _closeOnce();
                },
              ),
            ),
            _buildIcon(state.stage),
            const SizedBox(height: 20),
            Text(
              _labelFor(state),
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
            if (state.stage == VoiceOrderStage.needsClarification) ...[
              const SizedBox(height: 12),
              Text(
                'Hold the mic and answer',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon(VoiceOrderStage stage) {
    final busy = stage == VoiceOrderStage.transcribing ||
        stage == VoiceOrderStage.parsing ||
        stage == VoiceOrderStage.resolving ||
        stage == VoiceOrderStage.requestingPermission ||
        stage == VoiceOrderStage.listening;
    final isProblem = stage == VoiceOrderStage.error || stage == VoiceOrderStage.needsClarification;
    final isSuccess = stage == VoiceOrderStage.actionApplied;
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isProblem
            ? Colors.orange.withValues(alpha: 0.15)
            : isSuccess
                ? Colors.green.withValues(alpha: 0.15)
                : AppTheme.primaryColor.withValues(alpha: 0.15),
        border: Border.all(
          color: isProblem
              ? Colors.orange.shade300
              : isSuccess
                  ? Colors.green.shade400
                  : AppTheme.primaryColor,
          width: 2,
        ),
      ),
      child: Icon(
        isSuccess
            ? Icons.check_circle_rounded
            : isProblem
                ? Icons.help_outline_rounded
                : busy
                    ? Icons.hourglass_top_rounded
                    : Icons.mic_rounded,
        color: isProblem
            ? Colors.orange.shade300
            : isSuccess
                ? Colors.green.shade400
                : AppTheme.primaryColor,
        size: 40,
      ),
    );
  }

  String _labelFor(VoiceOrderState state) {
    switch (state.stage) {
      case VoiceOrderStage.requestingPermission:
        return 'Requesting microphone access...';
      case VoiceOrderStage.listening:
        return 'One sec...';
      case VoiceOrderStage.transcribing:
        return 'Got it — one sec...';
      case VoiceOrderStage.parsing:
        return 'Understanding...';
      case VoiceOrderStage.resolving:
        return 'Checking the menu...';
      case VoiceOrderStage.needsClarification:
        return state.errorMessage ?? 'Which one did you mean?';
      case VoiceOrderStage.actionApplied:
        return state.actionMessage ?? 'Done.';
      case VoiceOrderStage.error:
        return state.errorMessage ?? 'Something went wrong.';
      default:
        return 'One sec...';
    }
  }
}
