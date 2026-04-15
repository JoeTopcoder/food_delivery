/// Eastern Standard Time (UTC-5) helpers.
/// Cayman Islands does not observe daylight saving, so EST is used year-round.
class EstDateTime {
  EstDateTime._();

  /// The fixed EST offset: UTC − 5 hours.
  static const Duration offset = Duration(hours: -5);

  /// Current date-time in EST.
  static DateTime now() => DateTime.now().toUtc().add(offset);

  /// Convert any [DateTime] to EST.
  static DateTime fromUtc(DateTime utc) => utc.toUtc().add(offset);
}
