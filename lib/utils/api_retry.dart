import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'app_logger.dart';

/// Calls [fn] and retries on transient failures (429, 500, 503, network timeouts).
///
/// Strategy:
///   attempt 1 → immediate
///   attempt 2 → wait 1 s
///   attempt 3 → wait 2 s
///   attempt 4 → wait 4 s  (if [maxAttempts] >= 4)
///
/// 4xx errors OTHER than 429 are NOT retried (they indicate caller bugs).
Future<T> withRetry<T>(
  Future<T> Function() fn, {
  int maxAttempts = 3,
  String label = 'API',
}) async {
  int attempt = 0;
  while (true) {
    attempt++;
    try {
      return await fn();
    } on FunctionException catch (e) {
      final status = e.status;
      final retryable = status == 429 || status >= 500;
      if (!retryable || attempt >= maxAttempts) {
        AppLogger.error('[$label] FunctionException status=$status (attempt $attempt/$maxAttempts): $e');
        rethrow;
      }
      final delay = Duration(seconds: _backoffSeconds(attempt));
      AppLogger.warning('[$label] status=$status, retrying in ${delay.inSeconds}s (attempt $attempt/$maxAttempts)');
      await Future.delayed(delay);
    } on PostgrestException catch (e) {
      // PostgREST doesn't expose HTTP status cleanly; treat message hints as retryable
      final retryable = e.message.contains('timeout') || e.message.contains('connection');
      if (!retryable || attempt >= maxAttempts) {
        AppLogger.error('[$label] PostgrestException (attempt $attempt/$maxAttempts): ${e.message}');
        rethrow;
      }
      final delay = Duration(seconds: _backoffSeconds(attempt));
      AppLogger.warning('[$label] DB timeout, retrying in ${delay.inSeconds}s (attempt $attempt/$maxAttempts)');
      await Future.delayed(delay);
    } on TimeoutException catch (e) {
      if (attempt >= maxAttempts) {
        AppLogger.error('[$label] Timeout after $attempt attempts: $e');
        rethrow;
      }
      final delay = Duration(seconds: _backoffSeconds(attempt));
      AppLogger.warning('[$label] Timeout, retrying in ${delay.inSeconds}s (attempt $attempt/$maxAttempts)');
      await Future.delayed(delay);
    }
  }
}

int _backoffSeconds(int attempt) {
  // 1s, 2s, 4s … capped at 8s
  return (1 << (attempt - 1)).clamp(1, 8);
}
