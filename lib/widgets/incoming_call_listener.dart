import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/chat_model.dart';
import '../providers/auth_provider.dart';

/// Wraps the app and listens for incoming calls via Supabase realtime.
/// When a ringing call targets the current user, it auto-navigates to the
/// CallScreen as the receiver.
class IncomingCallListener extends ConsumerStatefulWidget {
  final Widget child;
  final GlobalKey<NavigatorState> navigatorKey;
  const IncomingCallListener({
    super.key,
    required this.child,
    required this.navigatorKey,
  });

  @override
  ConsumerState<IncomingCallListener> createState() =>
      _IncomingCallListenerState();
}

class _IncomingCallListenerState extends ConsumerState<IncomingCallListener> {
  RealtimeChannel? _channel;
  String? _currentUserId;
  String? _handledCallId; // Prevent duplicate navigation

  @override
  void initState() {
    super.initState();
    _setup();
  }

  void _setup() {
    final userId = ref.read(currentUserIdProvider);
    if (userId != null && userId.isNotEmpty) {
      _subscribe(userId);
    }
  }

  void _subscribe(String userId) {
    _currentUserId = userId;
    _channel?.unsubscribe();

    _channel = Supabase.instance.client
        .channel('incoming_calls_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'calls',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'receiver_id',
            value: userId,
          ),
          callback: _onCallInserted,
        )
        .subscribe();
  }

  void _onCallInserted(PostgresChangePayload payload) {
    final newRecord = payload.newRecord;
    if (newRecord.isEmpty) return;

    final status = newRecord['status'] as String? ?? '';
    final callId = newRecord['id'] as String? ?? '';

    // Only handle ringing calls, and prevent duplicate handling
    if (status != 'ringing') return;
    if (callId == _handledCallId) return;
    _handledCallId = callId;

    try {
      final call = CallRecord.fromJson(newRecord);
      final callerId = call.callerId;
      // Fetch caller's name then navigate
      Supabase.instance.client
          .from('users')
          .select('name')
          .eq('id', callerId)
          .maybeSingle()
          .then((row) {
            final callerName = row?['name'] as String?;
            widget.navigatorKey.currentState?.pushNamed(
              '/call',
              arguments: {
                'call': call,
                'isCaller': false,
                'otherPartyName': callerName,
              },
            );
          })
          .catchError((_) {
            // Fall back without name
            widget.navigatorKey.currentState?.pushNamed(
              '/call',
              arguments: {'call': call, 'isCaller': false},
            );
          });
    } catch (e) {
      if (kDebugMode) debugPrint('Error handling incoming call: $e');
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Watch for auth changes to subscribe/unsubscribe
    final userId = ref.watch(currentUserIdProvider);
    if (userId != _currentUserId) {
      if (userId != null && userId.isNotEmpty) {
        _subscribe(userId);
      } else {
        _channel?.unsubscribe();
        _currentUserId = null;
      }
    }

    return widget.child;
  }
}
