/// Abbreviates a customer's name for driver-facing UI: first initial + full
/// last name (e.g. "Joel Scott" -> "J Scott"). The driver never sees the
/// customer's full first name. Does not alter stored data — display only.
///
/// - null/empty -> "Customer"
/// - single word (no last name) -> that word unchanged
/// - collapses multiple spaces; a multi-word surname is kept whole
String formatDriverCustomerName(String? fullName) {
  if (fullName == null || fullName.trim().isEmpty) {
    return 'Customer';
  }

  final parts = fullName.trim().split(RegExp(r'\s+'));

  if (parts.length < 2) {
    return parts.first;
  }

  final firstInitial = parts.first.substring(0, 1).toUpperCase();
  final lastName = parts.sublist(1).join(' ');

  return '$firstInitial $lastName';
}
