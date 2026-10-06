import 'dart:convert';
import 'dart:io';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../utils/app_logger.dart';
import '../domain/models/parsed_voice_order.dart';

/// Sends a transcript (never audio) to the existing `ai-voice-assistant`
/// edge function for structured extraction only — no restaurant/menu
/// resolution happens here, and the response never carries a price. The
/// OpenAI API key lives server-side in that function's environment and
/// never touches this app.
class VoiceOrderParserService {
  VoiceOrderParserService(this._client);
  final SupabaseClient _client;

  /// Below this, the parse is treated as unparseable rather than acted on.
  static const confidenceThreshold = 0.5;

  /// [cartItemNames] — what's actually in the cart right now, by name —
  /// gives the parser real context to resolve "remove the Ting" /
  /// "make that two" against, without ever letting it invent a cart line
  /// that doesn't exist.
  Future<ParsedVoiceOrder?> parse({
    required String transcript,
    String? restaurantHint,
    List<String> cartItemNames = const [],
    List<Map<String, String>> history = const [],
  }) async {
    if (transcript.trim().isEmpty) return null;

    try {
      final session = _client.auth.currentSession;
      if (session == null) {
        throw Exception('Your session has expired. Please log in again.');
      }

      final response = await _client.functions.invoke(
        'ai-voice-assistant',
        body: {
          'mode': 'voice_order_parse',
          'transcript': transcript,
          if (restaurantHint != null) 'restaurant_hint': restaurantHint,
          if (cartItemNames.isNotEmpty) 'cart_item_names': cartItemNames,
          if (history.isNotEmpty) 'history': history,
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null || data.containsKey('error')) {
        AppLogger.error('VoiceOrderParserService: ${data?['error'] ?? 'empty response'}');
        return null;
      }

      final parsed = ParsedVoiceOrder.fromJson(data);
      if (parsed.confidence < confidenceThreshold ||
          parsed.intent == VoiceOrderIntent.unknown) {
        return null;
      }
      return parsed;
    } on FunctionException catch (e) {
      AppLogger.error('VoiceOrderParserService FunctionException: ${e.details}');
      return null;
    } catch (e) {
      AppLogger.error('VoiceOrderParserService error: $e');
      return null;
    }
  }

  /// Sends a recorded utterance to the edge function for server-side
  /// (Whisper) transcription — the fallback for devices whose on-device
  /// speech recognizer proves unreliable (confirmed on this app's own test
  /// hardware: on-device recognition repeatedly failed to extract words
  /// even when it detected speech). The audio file is deleted locally right
  /// after the upload attempt, success or failure — nothing lingers on
  /// disk, and nothing is stored server-side either (see the edge
  /// function's `voice_order_transcribe` handler).
  Future<String?> transcribe(String audioFilePath) async {
    final file = File(audioFilePath);
    try {
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;

      final session = _client.auth.currentSession;
      if (session == null) return null;

      final response = await _client.functions.invoke(
        'ai-voice-assistant',
        body: {
          'mode': 'voice_order_transcribe',
          'audio_base64': base64Encode(bytes),
          'mime_type': 'audio/m4a',
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null || data.containsKey('error')) {
        AppLogger.error('VoiceOrderParserService.transcribe: ${data?['error'] ?? 'empty response'}');
        return null;
      }
      return data['transcript'] as String?;
    } catch (e) {
      AppLogger.error('VoiceOrderParserService.transcribe error: $e');
      return null;
    } finally {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
  }
}
