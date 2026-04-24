import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/ai_voice_service.dart';
import '../services/speech_service.dart';
import '../utils/friendly_error.dart';

// ── Service providers ─────────────────────────────────────────────────────────

final aiVoiceServiceProvider = Provider<AiVoiceService>((ref) {
  return AiVoiceService(Supabase.instance.client);
});

// ── State ─────────────────────────────────────────────────────────────────────

enum AiVoiceStatus {
  idle,
  requestingPermission,
  listening,
  processing,
  speaking,
  error,
}

class AiVoiceMessage {
  final bool isUser;
  final String text;
  final DateTime at;

  /// When true, this message renders as a tappable call-driver card.
  final bool isDriverCallCard;
  final String? driverUserId;
  final String? driverName;

  const AiVoiceMessage({
    required this.isUser,
    required this.text,
    required this.at,
    this.isDriverCallCard = false,
    this.driverUserId,
    this.driverName,
  });
}

class AiVoiceState {
  final AiVoiceStatus status;
  final String transcribedText;
  final String aiResponseText;
  final List<AiVoiceMessage> history;
  final String? errorMessage;
  final bool micGranted;
  final bool canEscalate;
  final bool canEscalateToSupport; // true when intent == support_escalation
  final String lastIntent;
  final int? lastEtaMinutes;
  final List<AiCancelOrder>? pendingCancelOrders;
  final String? pendingDriverCallUserId; // non-null → screen should fire call
  final String? pendingDriverCallName;

  /// Phase 3: non-null when a backend action was auto-executed (credit, fraud flag, etc.)
  final AiAction? pendingAction;

  const AiVoiceState({
    this.status = AiVoiceStatus.idle,
    this.transcribedText = '',
    this.aiResponseText = '',
    this.history = const [],
    this.errorMessage,
    this.micGranted = false,
    this.canEscalate = false,
    this.canEscalateToSupport = false,
    this.lastIntent = 'general_question',
    this.lastEtaMinutes,
    this.pendingCancelOrders,
    this.pendingDriverCallUserId,
    this.pendingDriverCallName,
    this.pendingAction,
  });

  AiVoiceState copyWith({
    AiVoiceStatus? status,
    String? transcribedText,
    String? aiResponseText,
    List<AiVoiceMessage>? history,
    String? errorMessage,
    bool? micGranted,
    bool? canEscalate,
    bool? canEscalateToSupport,
    String? lastIntent,
    int? lastEtaMinutes,
    bool clearEta = false,
    List<AiCancelOrder>? pendingCancelOrders,
    bool clearCancelOrders = false,
    String? pendingDriverCallUserId,
    String? pendingDriverCallName,
    bool clearDriverCall = false,
    AiAction? pendingAction,
    bool clearPendingAction = false,
  }) => AiVoiceState(
    status: status ?? this.status,
    transcribedText: transcribedText ?? this.transcribedText,
    aiResponseText: aiResponseText ?? this.aiResponseText,
    history: history ?? this.history,
    errorMessage: errorMessage,
    micGranted: micGranted ?? this.micGranted,
    canEscalate: canEscalate ?? this.canEscalate,
    canEscalateToSupport: canEscalateToSupport ?? this.canEscalateToSupport,
    lastIntent: lastIntent ?? this.lastIntent,
    lastEtaMinutes: clearEta ? null : (lastEtaMinutes ?? this.lastEtaMinutes),
    pendingCancelOrders: clearCancelOrders
        ? null
        : (pendingCancelOrders ?? this.pendingCancelOrders),
    pendingDriverCallUserId: clearDriverCall
        ? null
        : (pendingDriverCallUserId ?? this.pendingDriverCallUserId),
    pendingDriverCallName: clearDriverCall
        ? null
        : (pendingDriverCallName ?? this.pendingDriverCallName),
    pendingAction: clearPendingAction
        ? null
        : (pendingAction ?? this.pendingAction),
  );
}

// ── Notifier ──────────────────────────────────────────────────────────────────

// ── Phase 3: AiAction model ───────────────────────────────────────────────────
class AiAction {
  /// Type: 'credit_issued' | 'fraud_flagged'
  final String type;
  final double? creditAmount;
  final String? creditReason;

  const AiAction({required this.type, this.creditAmount, this.creditReason});
}

class AiVoiceNotifier extends StateNotifier<AiVoiceState> {
  AiVoiceNotifier(this._service) : super(const AiVoiceState()) {
    _initSpeech();
  }

  final AiVoiceService _service;
  final SpeechService _speech = SpeechService.instance;

  String? _currentRole;
  String? _currentOrderId;
  String? _currentRestaurantId;
  int _consecutiveErrors = 0;

  // ── Auto system messages (no AI, fired by order status changes) ───────────
  static const _systemMessages = <String, String>{
    'confirmed': '✅ Your order has been confirmed by the restaurant.',
    'preparing': '👨‍🍳 The kitchen is now preparing your order.',
    'ready': '📦 Your order is ready and waiting for a driver.',
    'picked_up': '🛵 A driver has picked up your order and is on the way.',
    'out_for_delivery': '🛵 Your order is out for delivery!',
    'delivered': '🎉 Your order has been delivered. Enjoy your meal!',
    'cancelled': '❌ Your order has been cancelled.',
  };

  /// Call this when the order status changes (e.g. from a Realtime subscription).
  /// Injects a fast no-AI system message into the chat history and speaks it.
  Future<void> injectStatusUpdate(String newStatus) async {
    final msg = _systemMessages[newStatus];
    if (msg == null) return;
    final sysMsg = AiVoiceMessage(isUser: false, text: msg, at: DateTime.now());
    state = state.copyWith(
      history: [...state.history, sysMsg],
      aiResponseText: msg,
    );
    await _speak(msg);
  }

  Future<void> _initSpeech() async {
    await _speech.init();

    _speech.onSpeechResult = (text, isFinal) {
      state = state.copyWith(transcribedText: text);
      if (isFinal && text.trim().isNotEmpty) {
        _onFinalSpeech(text.trim());
      }
    };

    _speech.onListeningStarted = () => state = state.copyWith(
      status: AiVoiceStatus.listening,
      errorMessage: null,
    );

    _speech.onListeningStopped = () {
      if (state.status == AiVoiceStatus.listening) {
        state = state.copyWith(status: AiVoiceStatus.idle);
      }
    };

    _speech.onSpeakingStarted = () =>
        state = state.copyWith(status: AiVoiceStatus.speaking);

    _speech.onSpeakingCompleted = () =>
        state = state.copyWith(status: AiVoiceStatus.idle);

    _speech.onError = (msg) {
      state = state.copyWith(status: AiVoiceStatus.error, errorMessage: msg);
    };
  }

  /// Call once when opening the AI voice screen.
  Future<void> startSession({
    required String role,
    String? orderId,
    String? restaurantId,
  }) async {
    _currentRole = role;
    _currentOrderId = orderId;
    _currentRestaurantId = restaurantId;
    _consecutiveErrors = 0;

    final status = await Permission.microphone.status;
    if (!status.isGranted) {
      state = state.copyWith(status: AiVoiceStatus.requestingPermission);
      final result = await Permission.microphone.request();
      if (!result.isGranted) {
        state = state.copyWith(
          status: AiVoiceStatus.error,
          errorMessage:
              'Microphone permission is required for voice assistant.',
          micGranted: false,
        );
        return;
      }
    }
    state = state.copyWith(micGranted: true, status: AiVoiceStatus.idle);

    // Greet the user
    await _speak(_greetingFor(role));
  }

  /// Toggle mic on/off. If AI is speaking, interrupt it first.
  Future<void> toggleListening() async {
    if (state.status == AiVoiceStatus.speaking) {
      await _speech.interruptAndListen();
      return;
    }
    if (state.status == AiVoiceStatus.listening) {
      await _speech.stopListening();
      return;
    }
    if (!state.micGranted) {
      await startSession(
        role: _currentRole ?? 'customer',
        orderId: _currentOrderId,
        restaurantId: _currentRestaurantId,
      );
      return;
    }
    await _speech.startListening();
  }

  Future<void> _onFinalSpeech(String text) async {
    final userMsg = AiVoiceMessage(
      isUser: true,
      text: text,
      at: DateTime.now(),
    );
    state = state.copyWith(
      status: AiVoiceStatus.processing,
      history: [...state.history, userMsg],
      transcribedText: '',
    );

    try {
      final langCode = _speech.detectLanguage(text);
      final lang = langCode.split('-').first; // 'en', 'fr', etc.

      // Build history from prior turns only — exclude the current user message
      // (which was just appended to state.history) to avoid sending it twice.
      final priorHistory = state.history
          .take((state.history.length - 1).clamp(0, state.history.length))
          .map(
            (m) => {'role': m.isUser ? 'user' : 'assistant', 'content': m.text},
          )
          .toList();

      final result = await _service.ask(
        message: text,
        role: _currentRole ?? 'customer',
        orderId: _currentOrderId,
        restaurantId: _currentRestaurantId,
        language: lang,
        history: priorHistory,
      );

      _consecutiveErrors = 0;
      final aiMsg = AiVoiceMessage(
        isUser: false,
        text: result.response,
        at: DateTime.now(),
      );

      // Build history: AI text reply + optional call-card message
      final newHistory = [
        ...state.history,
        aiMsg,
        // If driver call intent, append a call-card bubble instead of auto-dialling
        if (result.driverUserId != null)
          AiVoiceMessage(
            isUser: false,
            text: '',
            at: DateTime.now(),
            isDriverCallCard: true,
            driverUserId: result.driverUserId,
            driverName: result.driverName ?? 'your driver',
          ),
      ];

      state = state.copyWith(
        aiResponseText: result.response,
        history: newHistory,
        canEscalate: false,
        canEscalateToSupport: result.intent == 'support_escalation',
        lastIntent: result.intent,
        lastEtaMinutes: result.etaMinutes,
        pendingCancelOrders: result.cancelOrders,
        // Phase 3: only surface visible actions to the UI (not fraud_flagged)
        pendingAction: result.action == 'credit_issued'
            ? AiAction(
                type: 'credit_issued',
                creditAmount: result.creditAmount,
                creditReason: result.creditReason,
              )
            : null,
      );

      await _speak(result.response, langCode: langCode);
    } catch (e) {
      _consecutiveErrors++;
      final errText =
          'Sorry, I had trouble with that. ${_consecutiveErrors >= 2 ? 'Would you like to speak to support?' : 'Please try again.'}';
      final aiMsg = AiVoiceMessage(
        isUser: false,
        text: errText,
        at: DateTime.now(),
      );
      state = state.copyWith(
        status: AiVoiceStatus.error,
        errorMessage: friendlyError(e),
        history: [...state.history, aiMsg],
        canEscalate: _consecutiveErrors >= 2,
      );
      await _speak(errText);
      if (kDebugMode) debugPrint('AiVoiceNotifier error: $e');
    }
  }

  Future<void> _speak(String text, {String? langCode}) async {
    state = state.copyWith(aiResponseText: text);
    await _speech.speak(text, langCode: langCode);
  }

  /// Type a message manually (text input fallback).
  Future<void> sendText(String text) async {
    if (text.trim().isEmpty) return;
    await _onFinalSpeech(text.trim());
  }

  Future<void> stopSpeaking() async {
    await _speech.stopSpeaking();
    state = state.copyWith(status: AiVoiceStatus.idle);
  }

  void clearHistory() => state = state.copyWith(history: []);

  /// Called by UI after cancel dialog is dismissed or completed.
  void dismissCancelOrders() => state = state.copyWith(clearCancelOrders: true);
  void dismissDriverCall() => state = state.copyWith(clearDriverCall: true);

  /// Phase 3: Called by UI after action banner is dismissed.
  void dismissAction() => state = state.copyWith(clearPendingAction: true);

  String _greetingFor(String role) {
    switch (role) {
      case 'driver':
        return 'Hi! I\'m your MealHub assistant. Ask me about your current delivery.';
      case 'admin':
        return 'Hi! I\'m the MealHub admin assistant. How can I help?';
      default:
        return 'Hi! I\'m your MealHub assistant. Ask me about your order or anything else.';
    }
  }

  @override
  void dispose() {
    _speech.stopListening();
    _speech.stopSpeaking();
    super.dispose();
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final aiVoiceProvider =
    StateNotifierProvider.autoDispose<AiVoiceNotifier, AiVoiceState>((ref) {
      final service = ref.watch(aiVoiceServiceProvider);
      return AiVoiceNotifier(service);
    });
