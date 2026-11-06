import '../models/catalog/menu_model.dart';

/// Whole-word (case-insensitive) match of any filter word against free text —
/// used for menu items and for search results that aren't [MenuItem]s.
bool isTextFiltered(String text, List<String> words) {
  if (words.isEmpty) return false;
  final hay = text.toLowerCase();
  for (final w in words) {
    if (w.isEmpty) continue;
    final pattern = RegExp(
      '(?<![a-z0-9])${RegExp.escape(w)}(?![a-z0-9])',
      caseSensitive: false,
    );
    if (pattern.hasMatch(hay)) return true;
  }
  return false;
}

/// Whether a menu item should be hidden from customers given the admin word
/// list. Matches whole words against the item's name, category and description
/// (case-insensitive), so a word like "cocktail" hides a whole "Signature
/// Cocktails" section. Owners/admins should NOT use this (they see everything).
bool isMenuFiltered(MenuItem item, List<String> words) => isTextFiltered(
    '${item.name} ${item.category} ${item.description ?? ''}', words);

/// Convenience: drop filtered items from a customer menu list.
List<MenuItem> applyMenuFilter(List<MenuItem> items, List<String> words) =>
    words.isEmpty
        ? items
        : items.where((m) => !isMenuFiltered(m, words)).toList();
