/// Formats a restaurant rating identically everywhere it is shown on a card.
///
/// - a real rating -> one decimal place (e.g. 4.3), never a raw 4.33333
/// - null or 0 (no ratings yet) -> "New", so a brand-new restaurant doesn't
///   show a misleading "0.0"
String formatRating(double? rating) {
  if (rating == null || rating <= 0) return 'New';
  return rating.toStringAsFixed(1);
}
