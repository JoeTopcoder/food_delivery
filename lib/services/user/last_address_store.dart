import 'package:shared_preferences/shared_preferences.dart';

/// Remembers the customer's LAST-USED delivery address id across app launches,
/// so when they reopen the app their previous address is preselected and the
/// delivery fee is calculated from it — until they pick a different one.
///
/// Backed by SharedPreferences with a synchronously-cached instance so Riverpod
/// providers can read it without awaiting. Call [init] once during app startup.
class LastAddressStore {
  static const _key = 'last_selected_address_id';
  static SharedPreferences? _prefs;

  /// Load the cached SharedPreferences instance (call once in main()).
  static Future<void> init() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (_) {
      // Non-fatal: the app still works, it just won't remember the address.
    }
  }

  /// The last-used address id, or null if none saved / prefs unavailable.
  static String? get lastUsed => _prefs?.getString(_key);

  /// Persist the last-used address id. Null/empty is ignored so a post-order
  /// reset does not wipe the remembered address for the next launch.
  static void save(String? id) {
    final p = _prefs;
    if (p == null || id == null || id.isEmpty) return;
    p.setString(_key, id);
  }

  /// Forget the saved address (e.g. on full sign-out).
  static Future<void> clear() async {
    await _prefs?.remove(_key);
  }
}
