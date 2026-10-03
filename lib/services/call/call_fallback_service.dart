import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../config/supabase_config.dart';

/// Reason a telephone fallback was requested. Matches the server's accepted set.
enum FallbackReason { connectTimeout, reconnectFailed, noAnswerManual }

extension on FallbackReason {
  String get wire => switch (this) {
        FallbackReason.connectTimeout => 'connect_timeout',
        FallbackReason.reconnectFailed => 'reconnect_failed',
        FallbackReason.noAnswerManual => 'no_answer_manual',
      };
}

/// Driver-facing phases of the telephone fallback. NEVER carries phone numbers.
enum FallbackPhase {
  idle,
  requesting,
  connectingByPhone,     // backend dialing the driver
  answerIncoming,        // driver must answer the incoming HotBite call
  callingCustomer,       // after press-1, backend dialing the customer
  phoneConnected,        // bridged
  customerNoAnswer,
  failed,
  cancelled,
}

class FallbackState {
  final FallbackPhase phase;
  final String? fallbackId;
  final bool mock;
  final String? message;
  const FallbackState(this.phase, {this.fallbackId, this.mock = false, this.message});
}

/// Separate service that bridges driver↔customer over the phone when the Agora
/// in-app call cannot connect/recover. It only ever submits order_id / call_id /
/// reason to the backend and polls a sanitized status — it never receives or
/// shows a phone number, and it does not run any audio of its own (no second
/// calling system). Agora remains the primary path.
class CallFallbackService {
  final _client = SupabaseConfig.client;
  Timer? _poll;

  /// Ask the backend to start a private phone bridge. Returns the fallback id, or
  /// null + a sanitized reason on failure. Does not expose phone numbers.
  Future<({bool ok, String? fallbackId, bool mock, String? reason})> request({
    required String orderId,
    String? callId,
    required FallbackReason reason,
  }) async {
    try {
      final res = await _client.functions.invoke(
        'call-fallback-request',
        body: {
          'order_id': orderId,
          'call_session_id': callId,
          'reason': reason.wire,
        },
      );
      final data = (res.data as Map?)?.cast<String, dynamic>() ?? {};
      if (data['ok'] == true) {
        return (
          ok: true,
          fallbackId: data['fallback_id'] as String?,
          mock: data['mock'] == true,
          reason: null,
        );
      }
      return (ok: false, fallbackId: null, mock: false, reason: data['reason']?.toString());
    } catch (e) {
      if (kDebugMode) debugPrint('CallFallbackService.request failed: $e');
      // Sanitized — never surface backend internals or numbers to the driver.
      return (ok: false, fallbackId: null, mock: false, reason: 'unavailable');
    }
  }

  /// Sanitized status for a fallback (driver-scoped RPC). No phone numbers.
  Future<String?> status(String fallbackId) async {
    try {
      final res = await _client
          .rpc('get_call_fallback_status', params: {'p_fallback_id': fallbackId});
      final m = (res as Map?)?.cast<String, dynamic>();
      return m?['status']?.toString();
    } catch (_) {
      return null;
    }
  }

  /// Cancel a still-pending fallback.
  Future<bool> cancel(String fallbackId) async {
    try {
      final res = await _client
          .rpc('cancel_call_fallback', params: {'p_fallback_id': fallbackId});
      return (res as Map?)?['ok'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Poll the sanitized status and map it to a driver-facing phase.
  void watch(String fallbackId, void Function(FallbackPhase) onPhase,
      {Duration every = const Duration(seconds: 3)}) {
    _poll?.cancel();
    _poll = Timer.periodic(every, (_) async {
      final s = await status(fallbackId);
      final phase = switch (s) {
        'requested' || 'dialing_driver' => FallbackPhase.connectingByPhone,
        'awaiting_driver_press' => FallbackPhase.answerIncoming,
        'dialing_customer' => FallbackPhase.callingCustomer,
        'bridged' => FallbackPhase.phoneConnected,
        'no_answer' => FallbackPhase.customerNoAnswer,
        'cancelled' => FallbackPhase.cancelled,
        'failed' => FallbackPhase.failed,
        _ => null,
      };
      if (phase != null) onPhase(phase);
      if (phase == FallbackPhase.phoneConnected ||
          phase == FallbackPhase.failed ||
          phase == FallbackPhase.cancelled ||
          phase == FallbackPhase.customerNoAnswer) {
        _poll?.cancel();
      }
    });
  }

  void dispose() {
    _poll?.cancel();
    _poll = null;
  }
}
