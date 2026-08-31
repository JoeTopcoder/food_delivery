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

/// One item Talk to Order resolved against the real menu — ids and
/// quantity only, never a price or name invented by the model. The caller
/// re-fetches the real [MenuItem] before mutating the cart.
class AiResolvedCartItem {
  final String menuItemId;
  final int quantity;
  final List<String> matchedSideIds;
  final List<String> matchedOptionChoiceIds;

  const AiResolvedCartItem({
    required this.menuItemId,
    required this.quantity,
    this.matchedSideIds = const [],
    this.matchedOptionChoiceIds = const [],
  });

  factory AiResolvedCartItem.fromJson(Map<String, dynamic> j) =>
      AiResolvedCartItem(
        menuItemId: j['menu_item_id'] as String,
        quantity: (j['quantity'] as num?)?.toInt() ?? 1,
        matchedSideIds:
            (j['matched_side_ids'] as List?)?.cast<String>() ?? const [],
        matchedOptionChoiceIds:
            (j['matched_option_choice_ids'] as List?)?.cast<String>() ??
            const [],
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

  /// Non-null when Talk to Order successfully resolved a real order — the
  /// app should apply these to the existing cart and navigate there.
  final String? cartResolutionRestaurantId;
  final String? cartResolutionRestaurantName;
  final List<AiResolvedCartItem>? cartResolutionItems;

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
    this.cartResolutionRestaurantId,
    this.cartResolutionRestaurantName,
    this.cartResolutionItems,
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
  /// [cartRestaurantId]/[cartItemCount] Current real-cart state, so Talk to
  /// Order can resolve requests like "add two Cokes" without a restaurant
  /// name and detect a restaurant-conflict before the app does.
  Future<AiVoiceResult> ask({
    required String message,
    required String role,
    String? orderId,
    String? restaurantId,
    String language = 'en',
    List<Map<String, String>> history = const [],
    String? cartRestaurantId,
    int? cartItemCount,
  }) async {
    try {
      // Force a session refresh so the SDK sends a fresh token.
      try {
        await _client.auth.refreshSession();
      } catch (_) {}

      // Always read the token AFTER the refresh attempt.
      final session = _client.auth.currentSession;
      if (session == null) {
        throw Exception('Your session has expired. Please log in again.');
      }

      final response = await _client.functions.invoke(
        'ai-voice-assistant',
        body: {
          'message': message,
          'role': role,
          if (orderId != null) 'order_id': orderId,
          if (restaurantId != null) 'restaurant_id': restaurantId,
          'language': language,
          if (history.isNotEmpty) 'history': history,
          if (cartRestaurantId != null) 'cart_restaurant_id': cartRestaurantId,
          if (cartItemCount != null) 'cart_item_count': cartItemCount,
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
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
        cartResolutionRestaurantId: data['action'] == 'cart_ready'
            ? (data['cart_resolution']
                      as Map<String, dynamic>?)?['restaurant']?['id']
                  as String?
            : null,
        cartResolutionRestaurantName: data['action'] == 'cart_ready'
            ? (data['cart_resolution']
                      as Map<String, dynamic>?)?['restaurant']?['name']
                  as String?
            : null,
        cartResolutionItems: data['action'] == 'cart_ready'
            ? ((data['cart_resolution']
                          as Map<String, dynamic>?)?['items']
                      as List?)
                  ?.map(
                    (i) => AiResolvedCartItem.fromJson(
                      Map<String, dynamic>.from(i as Map),
                    ),
                  )
                  .toList()
            : null,
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
