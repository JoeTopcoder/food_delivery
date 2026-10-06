import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/feature_providers.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/app_theme.dart';
import 'controllers/voice_order_controller.dart';
import 'voice_order_processing_sheet.dart';

/// "Talk to Order" entry point — a press-and-hold mic button. Press down to
/// start capturing, release to stop and process — the button itself
/// defines the recording window (push-to-talk), so there's never any
/// guessing about when the customer started or finished talking.
///
/// Deliberately shows NO overlay/route/dialog while held — only the
/// button's own look changes (bigger, darker). Opening anything else mid
/// -gesture risks disrupting the same pointer's release/cancel events (the
/// bug behind an earlier build's mic seeming unresponsive and its sheet
/// being impossible to close). Processing feedback only ever appears AFTER
/// release, in [showVoiceOrderProcessingSheet] — always freely dismissible.
///
/// Uses raw [Listener] (`onPointerDown/Up/Cancel`), not `GestureDetector`'s
/// tap recognizer — a tap recognizer cancels the whole gesture on a few
/// pixels of movement (`kTouchSlop`), which happens naturally on any real
/// multi-second hold and made the button feel broken in an earlier build.
///
/// Renders nothing when [voiceOrderingEnabledProvider] is false, so the
/// whole feature can be pulled from production remotely (app_config) with
/// zero redeploy and zero visible trace in the UI.
///
/// [restaurantHint] lets this be reused both on the Home screen (no
/// context) and inside a specific restaurant's screens.
class VoiceOrderButton extends ConsumerStatefulWidget {
  const VoiceOrderButton({super.key, this.restaurantHint});

  final String? restaurantHint;

  @override
  ConsumerState<VoiceOrderButton> createState() => _VoiceOrderButtonState();
}

class _VoiceOrderButtonState extends ConsumerState<VoiceOrderButton> {
  bool _pressed = false;

  // The pointer that started this hold — a hold is only ever ended by THIS
  // SAME pointer lifting or being cancelled, never a different finger.
  int? _activePointer;

  void _handlePressStart(int pointerId) {
    _activePointer = pointerId;
    setState(() => _pressed = true);
    final cartRestaurantId = ref.read(cartProvider.notifier).currentRestaurantId;
    ref.read(voiceOrderControllerProvider.notifier).beginCapture(
      restaurantHint: widget.restaurantHint,
      cartRestaurantId: cartRestaurantId,
    );
  }

  void _handlePressEnd(int pointerId) {
    if (!_pressed || pointerId != _activePointer) return;
    _activePointer = null;
    setState(() => _pressed = false);
    ref.read(voiceOrderControllerProvider.notifier).endCaptureAndProcess();
    showVoiceOrderProcessingSheet(context);
  }

  void _handlePressCancel(int pointerId) {
    if (!_pressed || pointerId != _activePointer) return;
    _activePointer = null;
    setState(() => _pressed = false);
    ref.read(voiceOrderControllerProvider.notifier).cancelCapture();
  }

  @override
  Widget build(BuildContext context) {
    final enabledAsync = ref.watch(voiceOrderingEnabledProvider);
    final enabled = enabledAsync.valueOrNull ?? false;
    if (!enabled) return const SizedBox.shrink();

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (e) => _handlePressStart(e.pointer),
      onPointerUp: (e) => _handlePressEnd(e.pointer),
      onPointerCancel: (e) => _handlePressCancel(e.pointer),
      child: AnimatedScale(
        scale: _pressed ? 1.25 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _pressed ? const Color(0xFFE0521A) : AppTheme.primaryColor,
            boxShadow: [
              BoxShadow(
                color: _pressed
                    ? const Color(0xFFE0521A).withValues(alpha: 0.6)
                    : Colors.black38,
                blurRadius: _pressed ? 16 : 8,
                spreadRadius: _pressed ? 2 : 0,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.mic_rounded, color: Colors.white),
        ),
      ),
    );
  }
}
