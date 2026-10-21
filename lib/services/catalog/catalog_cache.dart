import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../models/catalog/restaurant_model.dart';
import '../../models/catalog/menu_model.dart';
import '../../utils/app_logger.dart';

/// Disk-backed catalogue cache so the home grid and a restaurant's menu paint
/// instantly on a cold app launch, while fresh data loads in the background
/// (stale-while-revalidate).
///
/// Writes happen after a successful network load (from the providers). Reads
/// are synchronous off an in-memory mirror that [init] loads once at startup,
/// so the UI can seed its first frame without awaiting SharedPreferences.
///
/// The cache is a convenience, never the source of truth: everything here is
/// wrapped so a corrupt entry, a model change, or SharedPreferences being
/// unavailable (private mode, cleared data) degrades to "no cache" — the app
/// then simply shows its normal loading spinner, exactly as before.
class CatalogCache {
  CatalogCache._();

  static SharedPreferences? _prefs;
  static final Map<String, List<Restaurant>> _restaurants = {};
  static final Map<String, List<MenuItem>> _menus = {};

  static const String _rPrefix = 'catalog_rest_';
  static const String _mPrefix = 'catalog_menu_';

  /// Cap on how many restaurant menus we keep on disk, so the cache can't grow
  /// without bound as a customer browses. Oldest-written are dropped first.
  static const int _maxMenus = 50;

  /// Load the on-disk cache into memory. Call once during app startup, before
  /// the first frame. Safe to call more than once.
  static Future<void> init() async {
    try {
      final prefs = _prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys()) {
        if (key.startsWith(_rPrefix)) {
          final list = _decodeRestaurants(prefs.getString(key));
          if (list != null) _restaurants[key.substring(_rPrefix.length)] = list;
        } else if (key.startsWith(_mPrefix)) {
          final list = _decodeMenu(prefs.getString(key));
          if (list != null) _menus[key.substring(_mPrefix.length)] = list;
        }
      }
    } catch (e) {
      AppLogger.warning('CatalogCache init failed (ignored): $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Restaurant lists (keyed: 'all', 'top_rated', 'newly_added', 'breakfast',
  // 'must_try', …). The key namespaces each home section independently.
  // ---------------------------------------------------------------------------

  /// Synchronously returns the cached list for [key], or null if none.
  static List<Restaurant>? restaurants(String key) => _restaurants[key];

  /// Persist a freshly-loaded restaurant list. Updates the in-memory mirror
  /// immediately and writes through to disk best-effort.
  static Future<void> saveRestaurants(String key, List<Restaurant> list) async {
    _restaurants[key] = list;
    try {
      await _prefs?.setString(
        _rPrefix + key,
        jsonEncode(list.map((r) => r.toJson()).toList()),
      );
    } catch (e) {
      AppLogger.warning('CatalogCache.saveRestaurants($key) failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Per-restaurant menus (keyed by restaurant id).
  // ---------------------------------------------------------------------------

  /// Synchronously returns the cached menu for [restaurantId], or null if none.
  static List<MenuItem>? menu(String restaurantId) => _menus[restaurantId];

  /// Persist a freshly-loaded menu for [restaurantId].
  static Future<void> saveMenu(String restaurantId, List<MenuItem> list) async {
    _menus[restaurantId] = list;
    try {
      await _prefs?.setString(
        _mPrefix + restaurantId,
        jsonEncode(list.map((m) => m.toJson()).toList()),
      );
      await _trimMenus(restaurantId);
    } catch (e) {
      AppLogger.warning('CatalogCache.saveMenu($restaurantId) failed: $e');
    }
  }

  /// Keep at most [_maxMenus] menus on disk. We can't know true access order
  /// across launches, so this simply drops arbitrary other entries once the cap
  /// is exceeded, always keeping the one just written.
  static Future<void> _trimMenus(String keep) async {
    final prefs = _prefs;
    if (prefs == null || _menus.length <= _maxMenus) return;
    final ids = _menus.keys.where((id) => id != keep).toList();
    final overflow = _menus.length - _maxMenus;
    for (var i = 0; i < overflow && i < ids.length; i++) {
      _menus.remove(ids[i]);
      try {
        await prefs.remove(_mPrefix + ids[i]);
      } catch (_) {/* best-effort */}
    }
  }

  // ---------------------------------------------------------------------------

  static List<Restaurant>? _decodeRestaurants(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .map((e) => Restaurant.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null; // stale/incompatible shape — ignore, reload from network
    }
  }

  static List<MenuItem>? _decodeMenu(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      return decoded
          .map((e) => MenuItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }
}
