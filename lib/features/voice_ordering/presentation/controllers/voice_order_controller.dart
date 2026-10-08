import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../providers/auth_user/user_provider.dart';
import '../../../../services/ai/speech_service.dart';
import '../../../../services/food/menu_service.dart';
import '../../../../services/food/restaurant_service.dart';
import '../../data/voice_order_parser_service.dart';
import '../../data/voice_order_repository.dart';
import '../../domain/models/parsed_voice_order.dart';
import '../../domain/models/resolved_voice_order.dart';

/// Strict state machine. Any state can move to [error]; nothing here can
/// silently fail (every transition either advances or lands in [error]
/// with a message). [actionApplied] covers the low-risk cart-editing
/// intents (remove/update-quantity/clear) — applied immediately, always
/// visibly confirmed, never silent.
enum VoiceOrderStage {
  idle,
  requestingPermission,
  listening,
  transcribing,
  parsing,
  resolving,
  needsClarification,
  awaitingConfirmation,
  addingToCart,
  actionApplied,
  navigateToCart,
  done,
  error,
}

class VoiceOrderState {
  const VoiceOrderState({
    this.stage = VoiceOrderStage.idle,
    this.transcript = '',
    this.resolved,
    this.errorMessage,
    this.actionMessage,
  });

  final VoiceOrderStage stage;
  final String transcript;
  final ResolvedVoiceOrder? resolved;
  final String? errorMessage;
  final String? actionMessage;

  VoiceOrderState copyWith({
    VoiceOrderStage? stage,
    String? transcript,
    ResolvedVoiceOrder? resolved,
    String? errorMessage,
    String? actionMessage,
    bool clearResolved = false,
    bool clearError = false,
  }) => VoiceOrderState(
    stage: stage ?? this.stage,
    transcript: transcript ?? this.transcript,
    resolved: clearResolved ? null : (resolved ?? this.resolved),
    errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    actionMessage: actionMessage,
  );
}

/// Owns one voice-ordering session end to end. For [VoiceOrderIntent.
/// addToCart], never touches the cart itself — [VoiceOrderState.resolved]
/// is handed to the confirm screen, the only place THAT intent's cart
/// mutation happens, on explicit user confirm. The cart-editing intents
/// (remove/update-quantity/clear) are low-risk corrections applied
/// directly through the existing [CartNotifier] — always surfaced via
/// [VoiceOrderState.actionMessage], never silent.
class VoiceOrderController extends StateNotifier<VoiceOrderState> {
  VoiceOrderController(this._repository, this._ref) : super(const VoiceOrderState());

  final VoiceOrderRepository _repository;
  final Ref _ref;

  // Bumped on every beginCapture() call. An in-flight call whose token no
  // longer matches (a newer press started, or this controller was
  // disposed) writes nothing — prevents both a stale async result
  // clobbering a newer attempt's state AND the disposed-notifier crash
  // that happens when an old capture/parse/resolve resolves late.
  int _generation = 0;

  String? _restaurantHint;
  String? _cartRestaurantId;

  // Grows across turns within this session so a clarifying answer ("the
  // chicken one") is understood in context of the question just asked.
  // Reset on a fresh idle/retry, not on every press.
  final List<Map<String, String>> _history = [];

  // Completes once beginCapture() has actually reached the listening stage
  // (or given up) — endCaptureAndProcess() awaits this so a very fast
  // press-release doesn't race ahead of permission handling.
  Completer<bool>? _captureReady;

  /// Call the moment the customer presses the mic button down.
  Future<void> beginCapture({
    String? restaurantHint,
    String? cartRestaurantId,
  }) async {
    final myGeneration = ++_generation;
    await _repository.stopCapture();
    if (!mounted || myGeneration != _generation) return;

    _restaurantHint = restaurantHint;
    _cartRestaurantId = cartRestaurantId;
    _captureReady = Completer<bool>();

    state = state.stage == VoiceOrderStage.needsClarification
        ? state.copyWith(stage: VoiceOrderStage.requestingPermission)
        : const VoiceOrderState(stage: VoiceOrderStage.requestingPermission);

    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      final result = await Permission.microphone.request();
      if (!mounted || myGeneration != _generation) return;
      if (!result.isGranted) {
        state = state.copyWith(
          stage: VoiceOrderStage.error,
          errorMessage: result.isPermanentlyDenied
              ? 'Microphone access is off for 7Dash. Enable it in your device Settings to use Talk to Order.'
              : 'Microphone permission is required to use Talk to Order.',
        );
        if (!(_captureReady?.isCompleted ?? true)) _captureReady!.complete(false);
        return;
      }
    }
    if (!mounted || myGeneration != _generation) return;

    state = state.copyWith(stage: VoiceOrderStage.listening, transcript: '');
    await _repository.startCapture(
      onPartial: (text) {
        if (mounted &&
            myGeneration == _generation &&
            state.stage == VoiceOrderStage.listening) {
          state = state.copyWith(transcript: text);
        }
      },
    );
    if (!(_captureReady?.isCompleted ?? true)) _captureReady!.complete(true);
  }

  /// Call the moment the customer releases the mic button.
  Future<void> endCaptureAndProcess() async {
    final myGeneration = _generation;
    final ready = await (_captureReady?.future ?? Future.value(false))
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!mounted || myGeneration != _generation) return;
    if (!ready || state.stage != VoiceOrderStage.listening) return;

    state = state.copyWith(stage: VoiceOrderStage.transcribing);
    final transcript = await _repository.stopCaptureAndTranscribe();
    if (!mounted || myGeneration != _generation) return;

    if (transcript == null || transcript.trim().isEmpty) {
      state = state.copyWith(
        stage: VoiceOrderStage.error,
        errorMessage: "Didn't catch that — try again.",
      );
      return;
    }

    state = state.copyWith(transcript: transcript, stage: VoiceOrderStage.parsing);
    _history.add({'role': 'user', 'content': transcript});

    final cart = _ref.read(cartProvider);
    final parsed = await _repository.parse(
      transcript: transcript,
      restaurantHint: _restaurantHint,
      cartItemNames: cart.map((c) => c.menuItem.name).toList(),
      history: List.of(_history),
    );
    if (!mounted || myGeneration != _generation) return;
    if (parsed == null) {
      state = state.copyWith(
        stage: VoiceOrderStage.error,
        errorMessage:
            "I couldn't quite tell what you'd like. Try naming the restaurant and item, like \"jerk chicken from Island Grill\".",
      );
      return;
    }

    switch (parsed.intent) {
      case VoiceOrderIntent.addToCart:
        await _handleAddToCart(parsed, myGeneration);
        break;
      case VoiceOrderIntent.removeFromCart:
        _handleRemoveFromCart(parsed);
        break;
      case VoiceOrderIntent.updateQuantity:
        _handleUpdateQuantity(parsed);
        break;
      case VoiceOrderIntent.clearCart:
        _ref.read(cartProvider.notifier).clearCart();
        state = state.copyWith(stage: VoiceOrderStage.actionApplied, actionMessage: 'Cart cleared.');
        break;
      case VoiceOrderIntent.viewCart:
      case VoiceOrderIntent.checkout:
        state = state.copyWith(stage: VoiceOrderStage.navigateToCart);
        break;
      case VoiceOrderIntent.unknown:
        state = state.copyWith(
          stage: VoiceOrderStage.error,
          errorMessage: "I couldn't quite tell what you'd like — try again.",
        );
        break;
    }
  }

  Future<void> _handleAddToCart(ParsedVoiceOrder parsed, int myGeneration) async {
    state = state.copyWith(stage: VoiceOrderStage.resolving);
    final result = await _repository.resolveAddToCart(
      parsed,
      cartRestaurantId: _cartRestaurantId,
    );
    if (!mounted || myGeneration != _generation) return;

    if (result.clarificationQuestion != null) {
      _history.add({'role': 'assistant', 'content': result.clarificationQuestion!});
      state = state.copyWith(
        stage: VoiceOrderStage.needsClarification,
        errorMessage: result.clarificationQuestion,
      );
      return;
    }
    if (result.errorMessage != null) {
      state = state.copyWith(stage: VoiceOrderStage.error, errorMessage: result.errorMessage);
      return;
    }

    _history.clear(); // this order is settled; next press is a fresh command
    state = state.copyWith(stage: VoiceOrderStage.awaitingConfirmation, resolved: result.resolved);
  }

  void _handleRemoveFromCart(ParsedVoiceOrder parsed) {
    final cartNotifier = _ref.read(cartProvider.notifier);
    final cart = _ref.read(cartProvider);
    final reference = parsed.itemReference;
    if (reference == null) {
      state = state.copyWith(
        stage: VoiceOrderStage.error,
        errorMessage: 'Which item would you like to remove?',
      );
      return;
    }
    final match = _repository.findMatchingCartItem(cart, reference);
    if (match == null) {
      state = state.copyWith(
        stage: VoiceOrderStage.error,
        errorMessage: "I couldn't find \"$reference\" in your cart.",
      );
      return;
    }
    cartNotifier.removeItem(match.menuItem.id);
    state = state.copyWith(
      stage: VoiceOrderStage.actionApplied,
      actionMessage: 'Removed ${match.menuItem.name}.',
    );
  }

  void _handleUpdateQuantity(ParsedVoiceOrder parsed) {
    final cartNotifier = _ref.read(cartProvider.notifier);
    final cart = _ref.read(cartProvider);
    if (cart.isEmpty) {
      state = state.copyWith(stage: VoiceOrderStage.error, errorMessage: 'Your cart is empty.');
      return;
    }
    if (parsed.newQuantity == null) {
      state = state.copyWith(
        stage: VoiceOrderStage.error,
        errorMessage: "I didn't catch the new quantity — try again.",
      );
      return;
    }
    // No item named ("make that two") — apply to the single item in cart
    // if unambiguous, otherwise ask which one.
    final target = parsed.itemReference != null
        ? _repository.findMatchingCartItem(cart, parsed.itemReference!)
        : (cart.length == 1 ? cart.first : null);
    if (target == null) {
      state = state.copyWith(
        stage: VoiceOrderStage.error,
        errorMessage: parsed.itemReference != null
            ? "I couldn't find \"${parsed.itemReference}\" in your cart."
            : 'Which item would you like to change the quantity of?',
      );
      return;
    }
    cartNotifier.updateQuantity(target.menuItem.id, parsed.newQuantity!);
    state = state.copyWith(
      stage: VoiceOrderStage.actionApplied,
      actionMessage: parsed.newQuantity! <= 0
          ? 'Removed ${target.menuItem.name}.'
          : 'Updated ${target.menuItem.name} to ${parsed.newQuantity}.',
    );
  }

  /// Call if the press is cancelled rather than deliberately released
  /// (finger dragged off the button) — aborts back to idle, no processing.
  void cancelCapture() {
    _generation++;
    unawaited(_repository.stopCapture());
    if (!mounted) return;
    state = const VoiceOrderState();
  }

  /// Called by the confirm screen right before it mutates the cart, and
  /// after, to move through the last two states cleanly.
  void markAddingToCart() {
    if (!mounted) return;
    state = state.copyWith(stage: VoiceOrderStage.addingToCart);
  }

  void markDone() {
    if (!mounted) return;
    state = state.copyWith(stage: VoiceOrderStage.done);
  }

  void retry() {
    _generation++; // invalidate any still in-flight capture/process
    _history.clear();
    if (!mounted) return;
    state = const VoiceOrderState();
  }

  @override
  void dispose() {
    unawaited(_repository.stopCapture());
    super.dispose();
  }
}

final voiceOrderParserServiceProvider = Provider<VoiceOrderParserService>(
  (ref) => VoiceOrderParserService(Supabase.instance.client),
);

final voiceOrderRepositoryProvider = Provider<VoiceOrderRepository>((ref) {
  return VoiceOrderRepository(
    speechService: SpeechService.instance,
    parserService: ref.watch(voiceOrderParserServiceProvider),
    restaurantService: RestaurantService(Supabase.instance.client),
    menuService: MenuService(Supabase.instance.client),
  );
});

final voiceOrderControllerProvider =
    StateNotifierProvider.autoDispose<VoiceOrderController, VoiceOrderState>((ref) {
      return VoiceOrderController(ref.watch(voiceOrderRepositoryProvider), ref);
    });
