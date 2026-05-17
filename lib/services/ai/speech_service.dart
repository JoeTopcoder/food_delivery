import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';

/// Handles Speech-to-Text (STT) and Text-to-Speech (TTS) for the AI voice assistant.
/// Uses the device's native speech engine — no extra API key needed.
class SpeechService {
  SpeechService._();
  static final SpeechService instance = SpeechService._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();

  bool _speechAvailable = false;
  bool _isListening = false;
  bool _isSpeaking = false;

  // Callbacks
  void Function(String text, bool isFinal)? onSpeechResult;
  VoidCallback? onListeningStarted;
  VoidCallback? onListeningStopped;
  VoidCallback? onSpeakingStarted;
  VoidCallback? onSpeakingCompleted;
  void Function(String error)? onError;

  bool get isListening => _isListening;
  bool get isSpeaking => _isSpeaking;
  bool get speechAvailable => _speechAvailable;

  /// Initialize both STT and TTS engines. Call once at app/screen startup.
  Future<void> init() async {
    await _initStt();
    await _initTts();
  }

  Future<void> _initStt() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (e) {
          if (kDebugMode) debugPrint('STT error: ${e.errorMsg}');
          _isListening = false;
          onError?.call(_sttErrorMessage(e.errorMsg));
        },
        onStatus: (status) {
          if (kDebugMode) debugPrint('STT status: $status');
          if (status == 'done' || status == 'notListening') {
            _isListening = false;
            onListeningStopped?.call();
          }
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('STT init error: $e');
      _speechAvailable = false;
    }
  }

  Future<void> _initTts() async {
    await _tts.setLanguage('en-US');
    await _tts.setSpeechRate(0.48); // slightly slower for clarity
    await _tts.setVolume(1.0);
    await _tts.setPitch(1.0);

    _tts.setStartHandler(() {
      _isSpeaking = true;
      onSpeakingStarted?.call();
    });
    _tts.setCompletionHandler(() {
      _isSpeaking = false;
      onSpeakingCompleted?.call();
    });
    _tts.setErrorHandler((msg) {
      _isSpeaking = false;
      if (kDebugMode) debugPrint('TTS error: $msg');
    });
  }

  /// Start listening. Calls [onSpeechResult] with interim + final results.
  Future<void> startListening({String localeId = 'en_US'}) async {
    if (!_speechAvailable) {
      onError?.call('Speech recognition is not available on this device.');
      return;
    }
    if (_isListening) return;
    if (_isSpeaking) await stopSpeaking();

    _isListening = true;
    onListeningStarted?.call();

    await _speech.listen(
      onResult: (result) {
        onSpeechResult?.call(result.recognizedWords, result.finalResult);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3), // auto-stop after 3s silence
      localeId: localeId,
      listenOptions: stt.SpeechListenOptions(
        cancelOnError: false,
        partialResults: true,
      ),
    );
  }

  /// Stop listening and return the final recognised text.
  Future<void> stopListening() async {
    if (!_isListening) return;
    await _speech.stop();
    _isListening = false;
    onListeningStopped?.call();
  }

  /// Interrupt any ongoing speech and start listening immediately.
  Future<void> interruptAndListen({String localeId = 'en_US'}) async {
    await stopSpeaking();
    await startListening(localeId: localeId);
  }

  /// Speak the given text via TTS.
  Future<void> speak(String text, {String? langCode}) async {
    if (text.isEmpty) return;
    if (_isListening) await stopListening();

    if (langCode != null) await _tts.setLanguage(langCode);

    _isSpeaking = true;
    await _tts.speak(text);
  }

  /// Stop TTS playback.
  Future<void> stopSpeaking() async {
    if (!_isSpeaking) return;
    await _tts.stop();
    _isSpeaking = false;
  }

  /// Detect the language of a short text sample.
  /// Returns a BCP-47 locale string (e.g. 'en-US', 'es-ES').
  /// Falls back to 'en-US' if detection fails.
  String detectLanguage(String text) {
    // Basic heuristic — extend with langdetect package for production
    final lower = text.toLowerCase();
    if (RegExp(r'[àáâãäåæçèéêëìíîïðñòóôõöùúûüýþÿ]').hasMatch(lower)) {
      return 'fr-FR'; // or 'es-ES' — extend as needed
    }
    return 'en-US';
  }

  String _sttErrorMessage(String code) {
    switch (code) {
      case 'error_no_match':
        return "I didn't catch that. Please try again.";
      case 'error_speech_timeout':
        return 'No speech detected. Tap the mic to try again.';
      case 'error_network':
        return 'Network error. Please check your connection.';
      case 'error_permission':
        return 'Microphone permission is required.';
      default:
        return 'Speech recognition error. Please try again.';
    }
  }

  Future<void> dispose() async {
    await _speech.stop();
    await _tts.stop();
    _isListening = false;
    _isSpeaking = false;
  }
}
