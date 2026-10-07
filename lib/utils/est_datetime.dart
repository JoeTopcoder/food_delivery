import 'package:intl/intl.dart';

/// Jamaica time helpers. Jamaica (America/Jamaica) is UTC−5 ALL YEAR — it does
/// NOT observe daylight saving — so a fixed −5h offset is correct year-round.
/// (US Eastern switches to EDT/UTC−4 in summer, which is why relying on the
/// device locale or a US-Eastern tz gives times that are an hour off.)
///
/// Use these for DISPLAY so timestamps read as Jamaica local time regardless of
/// the device's timezone. Timestamps from Supabase are UTC.
class EstDateTime {
  EstDateTime._();

  /// Fixed Jamaica offset: UTC − 5 hours.
  static const Duration offset = Duration(hours: -5);

  /// Current date-time at Jamaica wall-clock.
  static DateTime now() => DateTime.now().toUtc().add(offset);

  /// Convert any [DateTime] to Jamaica wall-clock (safe whether the input is
  /// UTC or local). The result's fields read as Jamaica local time.
  static DateTime fromUtc(DateTime dt) => dt.toUtc().add(offset);

  /// Format any [DateTime] in Jamaica time with an intl [pattern].
  static String format(DateTime dt, String pattern) =>
      DateFormat(pattern).format(dt.toUtc().add(offset));
}

/// Display helpers so any timestamp renders in Jamaica local time.
extension JamaicaTime on DateTime {
  /// This instant expressed at Jamaica wall-clock (for formatting/display only).
  DateTime get toJamaica => toUtc().add(EstDateTime.offset);

  /// Format this timestamp in Jamaica time, e.g. `jmFormat('MMM d, y · h:mm a')`.
  String jmFormat(String pattern) => DateFormat(pattern).format(toJamaica);

  /// Short relative label ("just now", "5m ago", "2h ago", "3d ago", else date)
  /// computed against Jamaica "now".
  String get jmRelative {
    final diff = EstDateTime.now().difference(toJamaica);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return jmFormat('MMM d, y');
  }
}
