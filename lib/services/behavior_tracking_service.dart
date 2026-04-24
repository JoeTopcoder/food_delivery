import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/user_event_model.dart';
import '../utils/app_logger.dart';

/// Tracks every meaningful user interaction for the AI engine.
/// Fires events to Supabase via the `track_user_event` RPC.
class BehaviorTrackingService {
  final SupabaseClient _client;

  /// In-memory buffer for batching events (optional debounce).
  final List<Map<String, dynamic>> _buffer = [];
  static const _batchSize = 5;

  BehaviorTrackingService(this._client);

  /// Core tracking method — calls the `track_user_event` RPC.
  Future<void> trackEvent({
    required String userId,
    required String eventType,
    Map<String, dynamic> metadata = const {},
  }) async {
    try {
      await _client.rpc(
        'track_user_event',
        params: {
          'p_user_id': userId,
          'p_event_type': eventType,
          'p_metadata': metadata,
        },
      );
    } catch (e) {
      AppLogger.error('BehaviorTracking.trackEvent failed: $e');
      // Buffer for retry
      _buffer.add({
        'user_id': userId,
        'event_type': eventType,
        'metadata': metadata,
      });
      if (_buffer.length >= _batchSize) {
        _flushBuffer();
      }
    }
  }

  /// Flush buffered events in parallel (best-effort).
  Future<void> _flushBuffer() async {
    if (_buffer.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buffer);
    _buffer.clear();
    await Future.wait(
      batch.map(
        (evt) => _client
            .rpc(
              'track_user_event',
              params: {
                'p_user_id': evt['user_id'],
                'p_event_type': evt['event_type'],
                'p_metadata': evt['metadata'],
              },
            )
            .catchError((e) {
              AppLogger.error('BehaviorTracking.flush failed: $e');
            }),
      ),
    );
  }

  // ── Convenience helpers ──────────────────────────────────────

  Future<void> trackAppOpen(String userId) =>
      trackEvent(userId: userId, eventType: EventTypes.appOpen);

  Future<void> trackRestaurantView(
    String userId,
    String restaurantId, {
    String? cuisineType,
  }) => trackEvent(
    userId: userId,
    eventType: EventTypes.restaurantView,
    metadata: {
      'restaurant_id': restaurantId,
      if (cuisineType != null) 'cuisine': cuisineType,
    },
  );

  Future<void> trackMenuItemView(
    String userId,
    String menuItemId,
    String restaurantId,
  ) => trackEvent(
    userId: userId,
    eventType: EventTypes.menuItemView,
    metadata: {'menu_item_id': menuItemId, 'restaurant_id': restaurantId},
  );

  Future<void> trackAddToCart(
    String userId,
    String menuItemId, {
    double? price,
    String? category,
  }) => trackEvent(
    userId: userId,
    eventType: EventTypes.addToCart,
    metadata: {
      'menu_item_id': menuItemId,
      if (price != null) 'price': price,
      if (category != null) 'category': category,
    },
  );

  Future<void> trackRemoveFromCart(String userId, String menuItemId) =>
      trackEvent(
        userId: userId,
        eventType: EventTypes.removeFromCart,
        metadata: {'menu_item_id': menuItemId},
      );

  Future<void> trackOrderCompleted(
    String userId,
    String orderId,
    double total,
  ) => trackEvent(
    userId: userId,
    eventType: EventTypes.orderCompleted,
    metadata: {'order_id': orderId, 'total': total},
  );

  Future<void> trackSearch(String userId, String query) => trackEvent(
    userId: userId,
    eventType: EventTypes.searchQuery,
    metadata: {'query': query},
  );

  Future<void> trackCategoryTap(String userId, String category) => trackEvent(
    userId: userId,
    eventType: EventTypes.categoryTap,
    metadata: {'category': category},
  );

  Future<void> trackDealClicked(String userId, String restaurantId) =>
      trackEvent(
        userId: userId,
        eventType: EventTypes.dealClicked,
        metadata: {'restaurant_id': restaurantId},
      );

  Future<void> trackBannerTap(String userId, String bannerId) => trackEvent(
    userId: userId,
    eventType: EventTypes.bannerTap,
    metadata: {'banner_id': bannerId},
  );

  /// Get recent events for a user (for local adaptation).
  Future<List<UserEvent>> getRecentEvents(
    String userId, {
    int limit = 50,
  }) async {
    try {
      final response = await _client
          .from('user_events')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(limit);
      return (response as List).map((e) => UserEvent.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('BehaviorTracking.getRecentEvents failed: $e');
      return [];
    }
  }
}
