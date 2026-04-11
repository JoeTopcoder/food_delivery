// Simple logger without external dependencies

class AppLogger {
  static void debug(String message, [dynamic error, StackTrace? stackTrace]) {
    // print('$_tag [DEBUG] $message');
  }

  static void info(String message, [dynamic error, StackTrace? stackTrace]) {
    // print('$_tag [INFO] $message');
  }

  static void warning(String message, [dynamic error, StackTrace? stackTrace]) {
    // print('$_tag [WARN] $message');
  }

  static void error(String message, [dynamic error, StackTrace? stackTrace]) {
    // print('$_tag [ERROR] $message');
  }
}
