import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/chat_model.dart';

class ChatService {
  final SupabaseClient _client;
  ChatService(this._client);

  // ─── Messages (stream by order or ride) ────────────────────────────────────

  Stream<List<ChatMessage>> watchMessages({String? orderId, String? rideId}) {
    assert(orderId != null || rideId != null,
        'Must provide either orderId or rideId');
    final messages = <ChatMessage>[];
    RealtimeChannel? channel;

    final controller = StreamController<List<ChatMessage>>(
      onCancel: () => channel?.unsubscribe(),
    );

    // Initial fetch
    var query = _client.from('chat_messages').select();
    if (orderId != null) {
      query = query.eq('order_id', orderId);
    } else {
      query = query.eq('ride_id', rideId!);
    }
    query.order('created_at').then((data) {
      if (controller.isClosed) return;
      messages.addAll((data as List).map((e) => ChatMessage.fromJson(e)));
      controller.add(List.from(messages));
    }).catchError((Object e) {
      if (!controller.isClosed) controller.addError(e);
    });

    // Real-time inserts — filter client-side
    final channelName =
        orderId != null ? 'order_chat_$orderId' : 'ride_chat_$rideId';
    channel = _client
        .channel(channelName)
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) {
            if (controller.isClosed) return;
            final record = payload.newRecord;
            if (orderId != null && record['order_id'] != orderId) return;
            if (rideId != null && record['ride_id'] != rideId) return;
            try {
              final msg =
                  ChatMessage.fromJson(Map<String, dynamic>.from(record));
              if (!messages.any((m) => m.id == msg.id)) {
                messages.add(msg);
                messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
                controller.add(List.from(messages));
              }
            } catch (e) {
              if (kDebugMode) debugPrint('Message parse error: $e');
            }
          },
        )
        .subscribe();

    return controller.stream;
  }

  // ─── Send message (order or ride) ───────────────────────────────────────────

  Future<String?> sendMessage({
    String? orderId,
    String? rideId,
    required String senderId,
    required String senderRole,
    required String message,
    MessageType messageType = MessageType.text,
    Map<String, dynamic>? metadata,
  }) async {
    assert(orderId != null || rideId != null,
        'Must provide either orderId or rideId');
    try {
      String? result;
      if (rideId != null) {
        result = (await _client.rpc(
          'send_ride_message',
          params: {
            'p_ride_id': rideId,
            'p_message': message.trim(),
            'p_message_type': messageType.value,
            'p_metadata': metadata ?? {},
          },
        )) as String?;
      } else {
        result = (await _client.rpc(
          'send_message_secure',
          params: {
            'p_order_id': orderId,
            'p_message': message.trim(),
            'p_message_type': messageType.value,
            'p_metadata': metadata ?? {},
          },
        )) as String?;
      }

      // Send push notification for text messages
      if (messageType == MessageType.text) {
        _notifyNewMessage(
          orderId: orderId,
          rideId: rideId,
          senderId: senderId,
          message: message,
        );
      }

      return result;
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService.sendMessage error: $e');
      rethrow;
    }
  }

  /// Send FCM push to other conversation participants about a new message.
  Future<void> _notifyNewMessage({
    String? orderId,
    String? rideId,
    required String senderId,
    required String message,
  }) async {
    try {
      // Get sender name
      final senderRow = await _client
          .from('users')
          .select('name')
          .eq('id', senderId)
          .maybeSingle();
      final senderName = senderRow?['name'] as String? ?? 'Someone';

      // Get conversation participants
      var convQuery = _client.from('conversations').select('participant_ids');
      if (orderId != null) {
        convQuery = convQuery.eq('order_id', orderId);
      } else {
        convQuery = convQuery.eq('ride_id', rideId!);
      }
      final convRows = await convQuery.limit(1);
      if ((convRows as List).isEmpty) return;

      final participantIds = (convRows[0]['participant_ids'] as List<dynamic>)
          .map((e) => e as String)
          .where((id) => id != senderId)
          .toList();
      if (participantIds.isEmpty) return;

      // Get FCM tokens for all other participants
      final userRows =
          await _client.from('users').select('id, fcm_token').inFilter(
                'id',
                participantIds,
              );

      for (final row in (userRows as List)) {
        final fcmToken = row['fcm_token'] as String?;
        if (fcmToken == null || fcmToken.isEmpty) continue;

        await _client.functions.invoke(
          'send-fcm-notification',
          body: {
            'token': fcmToken,
            'title': senderName,
            'body': message.length > 100
                ? '${message.substring(0, 100)}...'
                : message,
            'data': {
              'type': 'new_message',
              if (orderId != null) 'order_id': orderId,
              if (rideId != null) 'ride_id': rideId,
              'sender_id': senderId,
              'sender_name': senderName,
              'user_id': row['id'] as String,
            },
          },
        );
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to send message notification: $e');
    }
  }

  // ─── Mark read (order or ride) ───────────────────────────────────────────

  Future<void> markRead({
    String? orderId,
    String? rideId,
    required String readerId,
  }) async {
    assert(orderId != null || rideId != null,
        'Must provide either orderId or rideId');
    try {
      var query = _client.from('conversations').select('id');
      if (orderId != null) {
        query = query.eq('order_id', orderId);
      } else {
        query = query.eq('ride_id', rideId!);
      }
      final convRows = await query.limit(1);
      if ((convRows as List).isNotEmpty) {
        final convId = convRows[0]['id'] as String;
        await _client.rpc(
          'mark_messages_status',
          params: {'p_conversation_id': convId, 'p_new_status': 'seen'},
        );
      } else if (orderId != null) {
        // Fallback: direct update for old messages without conversations
        await _client
            .from('chat_messages')
            .update({'is_read': true})
            .eq('order_id', orderId)
            .neq('sender_id', readerId);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('ChatService.markRead error: $e');
    }
  }

  // ─── Mark message status (delivered/seen) ─────────────────────────────────

  Future<void> markStatus(String conversationId, String status) async {
    await _client.rpc(
      'mark_messages_status',
      params: {'p_conversation_id': conversationId, 'p_new_status': status},
    );
  }

  // ─── Unread count ────────────────────────────────────────────────────────

  Future<int> unreadCount(String orderId, String userId) async {
    final res = await _client
        .from('chat_messages')
        .select('id')
        .eq('order_id', orderId)
        .eq('is_read', false)
        .neq('sender_id', userId);
    return (res as List).length;
  }

  // ─── Conversations ───────────────────────────────────────────────────────

  Stream<List<Conversation>> watchConversations() {
    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .order('last_message_at', ascending: false)
        .map((rows) => rows.map((e) => Conversation.fromJson(e)).toList());
  }

  Future<Conversation?> getConversationForOrder(String orderId) async {
    final rows = await _client
        .from('conversations')
        .select()
        .eq('order_id', orderId)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return Conversation.fromJson(rows[0]);
  }

  Future<Conversation?> getConversationForRide(String rideId) async {
    final rows = await _client
        .from('conversations')
        .select()
        .eq('ride_id', rideId)
        .limit(1);
    if ((rows as List).isEmpty) return null;
    return Conversation.fromJson(rows[0]);
  }

  // ─── Typing indicators ──────────────────────────────────────────────────

  Future<void> setTyping(String conversationId, bool isTyping) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return;
    await _client.from('typing_indicators').upsert({
      'conversation_id': conversationId,
      'user_id': userId,
      'is_typing': isTyping,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'conversation_id,user_id');
  }

  Stream<List<Map<String, dynamic>>> watchTyping(String conversationId) {
    return _client
        .from('typing_indicators')
        .stream(primaryKey: ['id'])
        .eq('conversation_id', conversationId)
        .map((rows) => rows.where((r) => r['is_typing'] == true).toList());
  }


  // ─── Calls ───────────────────────────────────────────────────────────────

  /// Fetch an Agora RTC token from the edge function.
  Future<({String token, String appId})?> fetchAgoraToken(
    String callId,
    String channelName,
  ) async {
    try {
      if (kDebugMode) {
        debugPrint(
          'Agora token: invoking edge function callId=$callId channel=$channelName',
        );
      }
      // Refresh session to avoid UNAUTHORIZED_LEGACY_JWT with stale HS256 tokens.
      try {
        await _client.auth.refreshSession();
      } catch (_) {}
      final session = _client.auth.currentSession;
      final headers = session != null
          ? {'Authorization': 'Bearer ${session.accessToken}'}
          : <String, String>{};

      final res = await _client.functions.invoke(
        'agora-token',
        body: {'callId': callId, 'channelName': channelName},
        headers: headers,
      );
      if (kDebugMode) {
        debugPrint(
          'Agora token: response status=${res.status} type=${res.data.runtimeType}',
        );
      }
      if (res.data is Map<String, dynamic>) {
        final data = res.data as Map<String, dynamic>;
        if (data.containsKey('error')) {
          if (kDebugMode)
            debugPrint('Agora token: server error: ${data['error']}');
          throw Exception('Server: ${data['error']}');
        }
        final serverAppId = data['appId'] as String? ?? '';
        final token = data['token'] as String?;
        if (kDebugMode) {
          debugPrint(
            'Agora token: got token ${token?.length ?? 0} chars, appId=${serverAppId.isNotEmpty ? serverAppId.substring(0, 8) : "EMPTY"}...',
          );
        }
        if (token != null && token.isNotEmpty) {
          return (token: token, appId: serverAppId);
        }
        throw Exception('Token missing from response');
      }
      throw Exception('Bad response type: ${res.data.runtimeType}');
    } on FunctionException catch (e) {
      // FunctionException carries the HTTP status and body
      if (kDebugMode) {
        debugPrint(
          'Agora token: FunctionException status=${e.status} details=${e.details}',
        );
      }
      final details = e.details;
      String msg = 'HTTP ${e.status}';
      if (details is Map<String, dynamic> && details.containsKey('error')) {
        msg = '${e.status}: ${details['error']}';
      } else if (details != null) {
        msg = '${e.status}: $details';
      }
      throw Exception(msg);
    } catch (e) {
      if (kDebugMode) debugPrint('Failed to fetch Agora token: $e');
      rethrow;
    }
  }

  Future<CallRecord> initiateCall({
    required String orderId,
    required String receiverId,
  }) async {
    final callerId = _client.auth.currentUser!.id;

    // Use server-side RPC that resolves driver_id → user_id automatically
    // This bypasses RLS restrictions on the drivers table
    final res = await _client.rpc(
      'initiate_call',
      params: {'p_order_id': orderId, 'p_receiver_id': receiverId},
    );

    final callJson = res as Map<String, dynamic>;
    var callRecord = CallRecord.fromJson(callJson);

    // Fetch Agora token so both parties can join the channel
    try {
      final result = await fetchAgoraToken(
        callRecord.id,
        callRecord.channelName,
      );
      if (result != null) {
        callRecord = callRecord.copyWith(agoraToken: result.token);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint(
          'initiateCall: token pre-fetch failed (will retry in CallScreen): $e',
        );
      }
    }

    // Send a system message about the call (no-op for rides — no conversation)
    try {
      await sendMessage(
        orderId: orderId,
        senderId: callerId,
        senderRole: '',
        message: 'Voice call started',
        messageType: MessageType.callEvent,
      );
    } catch (e) {
      if (kDebugMode) debugPrint('initiateCall: system message skipped: $e');
    }

    // Send FCM push notification to receiver so their phone rings
    _notifyIncomingCall(callRecord);

    return callRecord;
  }

  /// Sends an FCM push notification to the receiver for an incoming call.
  /// Uses the dedicated send-call-notification edge function which handles
  /// FCM token lookup and high-priority data-only message delivery.
  Future<void> _notifyIncomingCall(CallRecord call) async {
    try {
      // Get caller name for the notification
      final callerRow = await _client
          .from('users')
          .select('name')
          .eq('id', call.callerId)
          .maybeSingle();
      final callerName = callerRow?['name'] as String? ?? 'Someone';

      // Invoke the dedicated call notification edge function
      // It fetches the recipient's FCM token server-side and sends
      // a high-priority data-only FCM message so the phone rings
      await _client.functions.invoke(
        'send-call-notification',
        body: {
          'recipientUserId': call.receiverId,
          'callerName': callerName,
          'callId': call.id,
          'callerId': call.callerId,
          'orderId': call.orderId,
          'channelName': call.channelName,
        },
      );
    } catch (e) {
      // Non-critical — the realtime listener will also pick up the call
      if (kDebugMode) debugPrint('Failed to send call notification: $e');
    }
  }

  Future<void> updateCallStatus(String callId, CallStatus status) async {
    final updates = <String, dynamic>{'status': status.value};
    if (status == CallStatus.accepted) {
      updates['started_at'] = DateTime.now().toUtc().toIso8601String();
    }
    if (status == CallStatus.ended ||
        status == CallStatus.missed ||
        status == CallStatus.declined ||
        status == CallStatus.failed) {
      updates['ended_at'] = DateTime.now().toUtc().toIso8601String();
      // Clear stale token so the next call always gets a fresh one
      updates['agora_token'] = null;
    }
    await _client.from('calls').update(updates).eq('id', callId);
  }

  /// Fetch a single call record by ID (to get the agora_token from the DB).
  Future<CallRecord?> getCallById(String callId) async {
    final row = await _client
        .from('calls')
        .select()
        .eq('id', callId)
        .maybeSingle();
    if (row == null) return null;
    return CallRecord.fromJson(row);
  }

  Stream<List<CallRecord>> watchActiveCalls(String userId) {
    // Listen to ALL calls for this user — don't filter by status on the stream.
    // Supabase .stream() with .inFilter silently drops rows that leave the
    // filter set, so the listener never learns the call was ended/declined.
    return _client
        .from('calls')
        .stream(primaryKey: ['id'])
        .map(
          (rows) => rows
              .where(
                (r) =>
                    (r['caller_id'] == userId || r['receiver_id'] == userId) &&
                    (r['status'] == 'ringing' ||
                        r['status'] == 'accepted' ||
                        r['status'] == 'ended' ||
                        r['status'] == 'declined' ||
                        r['status'] == 'missed'),
              )
              .map((r) => CallRecord.fromJson(r))
              .toList(),
        );
  }

  // ─── Order issues ────────────────────────────────────────────────────────

  Future<void> reportIssue({
    required String orderId,
    required String userId,
    required String issueType,
    required String description,
  }) async {
    await _client.from('order_issues').insert({
      'order_id': orderId,
      'user_id': userId,
      'issue_type': issueType,
      'description': description,
      'status': 'open',
    });
  }

  Future<List<OrderIssue>> getIssues({String? orderId, String? userId}) async {
    var query = _client.from('order_issues').select();
    if (orderId != null) query = query.eq('order_id', orderId);
    if (userId != null) query = query.eq('user_id', userId);
    final res = await query.order('created_at', ascending: false);
    return (res as List).map((e) => OrderIssue.fromJson(e)).toList();
  }

  Future<List<OrderIssue>> getAllIssues() async {
    final res = await _client
        .from('order_issues')
        .select()
        .order('created_at', ascending: false);
    return (res as List).map((e) => OrderIssue.fromJson(e)).toList();
  }

  // ─── Support / Admin ─────────────────────────────────────────────────────

  /// Returns the ID of any admin user, for customer → admin support calls.
  Future<String?> getAnAdminUserId() async {
    final rows = await _client
        .from('users')
        .select('id')
        .eq('role', 'admin')
        .limit(1);
    final list = rows as List;
    if (list.isEmpty) return null;
    return list.first['id'] as String?;
  }

  Future<List<Map<String, dynamic>>> getAllChatSummaries() async {
    // Use conversations table for better performance
    final convs = await _client
        .from('conversations')
        .select()
        .order('last_message_at', ascending: false);
    if ((convs as List).isNotEmpty) {
      return convs.cast<Map<String, dynamic>>();
    }
    // Fallback to old method
    final res = await _client
        .from('chat_messages')
        .select('order_id, message, sender_role, created_at')
        .order('created_at', ascending: false);
    final rows = res as List;
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final row in rows) {
      final oid = row['order_id'] as String;
      if (!grouped.containsKey(oid)) {
        grouped[oid] = row;
      }
    }
    return grouped.values.toList();
  }
}
