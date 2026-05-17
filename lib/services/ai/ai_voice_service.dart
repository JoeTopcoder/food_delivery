import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_logger.dart';

/// Result from the AI voice assistant edge function.
class AiCancelOrder {
  final String id;
  final String shortId;
  final String restaurant;
  final String status;
  final double total;

  const AiCancelOrder({
    required this.id,
    required this.shortId,
    required this.restaurant,
    required this.status,
    required this.total,
  });

  factory AiCancelOrder.fromJson(Map<String, dynamic> j) => AiCancelOrder(
    id: j['id'] as String,
    shortId: j['shortId'] as String,
    restaurant: j['restaurant'] as String,
    status: j['status'] as String,
    total: (j['total'] as num).toDouble(),
  );
}

class AiVoiceResult {
  final String response;
  final bool hasOrderContext;
  final String intent;
  final int? etaMinutes;

  /// Non-null when AI wants the app to show an order-selection cancel dialog.
  final List<AiCancelOrder>? cancelOrders;

  /// Non-null when AI wants to fire a driver call directly.
  final String? driverUserId;
  final String? driverName;

  // ── Phase 3 fields ───────────────────────────────────────────────────────
  /// Action type from edge function: credit_issued | fraud_flagged | null
  final String? action;

  /// Credit amount (when action == 'credit_issued')
  final double? creditAmount;

  /// Credit reason text (when action == 'credit_issued')
  final String? creditReason;

  /// Sentiment detected by edge function: calm | frustrated | angry | urgent
  final String sentiment;

  /// Whether the order is delayed
  final bool isDelayed;

  /// Delay duration in minutes
  final int delayMinutes;

  const AiVoiceResult({
    required this.response,
    required this.hasOrderContext,
    this.intent = 'general_question',
    this.etaMinutes,
    this.cancelOrders,
    this.driverUserId,
    this.driverName,
    this.action,
    this.creditAmount,
    this.creditReason,
    this.sentiment = 'calm',
    this.isDelayed = false,
    this.delayMinutes = 0,
  });
}

/// Calls the `ai-voice-assistant` Supabase edge function with user message + context.
class AiVoiceService {
  AiVoiceService(this._client);
  final SupabaseClient _client;

  /// Send a voice-transcribed message to the AI and get a text response back.
  ///
  /// [message]  The user's transcribed speech.
  /// [role]     The authenticated user's role: customer | driver | admin.
  /// [orderId]  Optional — if provided, AI fetches live order context.
  /// [restaurantId] Optional — if provided, AI fetches menu & restaurant context.
  /// [language] BCP-47 language code, e.g. 'en', 'es'. Defaults to 'en'.
  /// [history]  Prior conversation turns for multi-turn memory.
  Future<AiVoiceResult> ask({
    required String message,
    required String role,
    String? orderId,
    String? restaurantId,
    String language = 'en',
    List<Map<String, String>> history = const [],
  }) async {
    try {
      // Refresh session to ensure we have a valid RS256 JWT (not a legacy HS256 token).
      // UNAUTHORIZED_LEGACY_JWT errors occur when a stale token is sent.
      try {
        await _client.auth.refreshSession();
      } catch (_) {}

      // Explicitly pass the refreshed access token.
      final session = _client.auth.currentSession;
      final headers = session != null
          ? {'Authorization': 'Bearer ${session.accessToken}'}
          : <String, String>{};

      final response = await _client.functions.invoke(
        'ai-voice-assistant',
        body: {
          'message': message,
          'role': role,
          if (orderId != null) 'order_id': orderId,
          if (restaurantId != null) 'restaurant_id': restaurantId,
          'language': language,
          if (history.isNotEmpty) 'history': history,
        },
        headers: headers,
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null) throw Exception('Empty response from AI service');

      if (data.containsKey('error')) {
        throw Exception(data['error']);
      }

      return AiVoiceResult(
        response: data['response'] as String? ?? '',
        hasOrderContext: data['context'] == 'order_found',
        intent: data['intent'] as String? ?? 'general_question',
        etaMinutes: data['eta_minutes'] as int?,
        cancelOrders: data['action'] == 'select_order_to_cancel'
            ? (data['orders'] as List?)
                  ?.map(
                    (o) => AiCancelOrder.fromJson(
                      Map<String, dynamic>.from(o as Map),
                    ),
                  )
                  .toList()
            : null,
        driverUserId: data['action'] == 'call_driver'
            ? data['driver_user_id'] as String?
            : null,
        driverName: data['driver_name'] as String?,
        action: data['action'] as String?,
        creditAmount: data['credit_amount'] != null
            ? (data['credit_amount'] as num).toDouble()
            : null,
        creditReason: data['credit_reason'] as String?,
        sentiment: data['sentiment'] as String? ?? 'calm',
        isDelayed: data['is_delayed'] as bool? ?? false,
        delayMinutes: (data['delay_minutes'] as num?)?.toInt() ?? 0,
      );
    } on FunctionException catch (e) {
      AppLogger.error('AiVoiceService FunctionException: ${e.details}');
      rethrow;
    } catch (e) {
      AppLogger.error('AiVoiceService error: $e');
      rethrow;
    }
  }

  /// Fetch conversation history for current user (last [limit] turns).
  Future<List<AiConversationTurn>> getHistory({int limit = 20}) async {
    try {
      final rows = await _client
          .from('ai_voice_sessions')
          .select('user_message, ai_response, created_at')
          .order('created_at', ascending: false)
          .limit(limit);

      return (rows as List)
          .map((r) => AiConversationTurn.fromJson(r as Map<String, dynamic>))
          .toList()
          .reversed
          .toList();
    } catch (e) {
      AppLogger.error('AiVoiceService.getHistory error: $e');
      return [];
    }
  }
}

class AiConversationTurn {
  final String userMessage;
  final String aiResponse;
  final DateTime createdAt;

  const AiConversationTurn({
    required this.userMessage,
    required this.aiResponse,
    required this.createdAt,
  });

  factory AiConversationTurn.fromJson(Map<String, dynamic> json) =>
      AiConversationTurn(
        userMessage: json['user_message'] as String,
        aiResponse: json['ai_response'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
}
