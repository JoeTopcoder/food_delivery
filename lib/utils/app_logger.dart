// Simple logger — prints only in debug mode, tree-shaken in release builds
import 'package:flutter/foundation.dart';

class AppLogger {
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) debugPrint('[DEBUG] $message');
  }

  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) debugPrint('[INFO] $message');
  }

  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) debugPrint('[WARN] $message');
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    if (kDebugMode) debugPrint('[ERROR] $message${error != null ? ': $error' : ''}');
    if (kDebugMode && stackTrace != null) debugPrint(stackTrace.toString());
  }
}
