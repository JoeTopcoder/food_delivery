/// PostgREST returns PostgreSQL NUMERIC/DECIMAL columns as JSON strings.
/// This helper safely parses both String and num values to double.
double? parseDouble(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

double parseDoubleRequired(dynamic v, {double fallback = 0.0}) =>
    parseDouble(v) ?? fallback;
